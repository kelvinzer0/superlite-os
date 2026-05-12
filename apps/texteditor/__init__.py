"""Text Editor - Lightweight code editor with scroll-synced line numbers"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, Gio, GLib, Pango
import os

try:
    from core.decorations import apply_titlebar
    from core.theme import get_theme
except ImportError:
    from decorations import apply_titlebar
    from theme import get_theme

_CSS_DONE = False

def _ensure_css():
    global _CSS_DONE
    if _CSS_DONE:
        return
    d = Gdk.Display.get_default()
    if not d:
        return
    _CSS_DONE = True
    theme = get_theme()
    css = f"""
    .editor-menu {{
        background: {theme.surface};
        padding: 2px 4px;
        border-bottom: 1px solid {theme.border};
    }}
    .editor-menu-btn {{
        background: transparent;
        color: {theme.text_mid};
        border: none;
        padding: 4px 10px;
    }}
    .editor-menu-btn:hover {{
        background: {theme.surface_alt};
        color: {theme.text_bright};
    }}
    .editor-toolbar {{
        background: {theme.surface_alt};
        padding: 4px 8px;
        border-bottom: 1px solid {theme.border};
    }}
    .editor-tool-btn {{
        background: transparent;
        color: {theme.text_mid};
        border: 1px solid {theme.border};
        border-radius: 3px;
        padding: 2px 8px;
        font-size: 14px;
    }}
    .editor-tool-btn:hover {{
        background: {theme.border};
        color: {theme.text_bright};
    }}
    .editor-line-numbers {{
        background: {theme.bg};
        color: {theme.text_dim};
        font-size: 12px;
        padding: 4px;
        border-right: 1px solid {theme.surface_alt};
    }}
    .editor-text {{
        background: {theme.bg};
        color: {theme.text_bright};
        font-size: 13px;
        caret-color: {theme.caret};
    }}
    .editor-status {{
        background: {theme.surface};
        color: {theme.text_dim};
        padding: 4px 8px;
        font-size: 11px;
        border-top: 1px solid {theme.surface_alt};
    }}
    """
    p = Gtk.CssProvider()
    p.load_from_data(css.encode())
    Gtk.StyleContext.add_provider_for_display(d, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


class TextEditorWindow(Gtk.Window):
    def __init__(self, filepath=None):
        super().__init__()
        self.set_title("Text Editor")
        self.set_default_size(900, 600)
        self.current_file = None
        self.modified = False
        self._undo_stack: list[str] = []
        self._redo_stack: list[str] = []
        _ensure_css()
        apply_titlebar(self, icon="📝", title="Text Editor")

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(main)

        # Menu
        menu = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        menu.add_css_class("editor-menu")
        for label, items in {
            "File": [("New", self._new), ("Open", self._open), ("Save", self._save)],
            "Edit": [("Undo", self._undo), ("Redo", self._redo), ("Cut", self._cut),
                     ("Copy", self._copy), ("Paste", self._paste), ("Select All", self._select_all)],
        }.items():
            btn = Gtk.MenuButton(label=label)
            btn.add_css_class("editor-menu-btn")
            m = Gio.Menu()
            for il, cb in items:
                a = Gio.SimpleAction.new(il.lower().replace(" ", "-"), None)
                a.connect("activate", lambda _, __, c=cb: c())
                self.add_action(a)
                m.append(il, f"win.{il.lower().replace(' ', '-')}")
            btn.set_menu_model(m)
            menu.append(btn)
        main.append(menu)

        # Toolbar
        tb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        tb.add_css_class("editor-toolbar")
        for lbl, tip, cb in [("📄","New",self._new),("📂","Open",self._open),("💾","Save",self._save)]:
            b = Gtk.Button(label=lbl)
            b.set_tooltip_text(tip)
            b.add_css_class("editor-tool-btn")
            b.connect("clicked", lambda _, c=cb: c())
            tb.append(b)
        sp = Gtk.Box(); sp.set_hexpand(True); tb.append(sp)
        self.lang = Gtk.Label(label="Plain Text")
        tb.append(self.lang)
        main.append(tb)

        # Editor — line numbers + text in same scrolled window for sync
        ed = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        ed.set_vexpand(True)

        # ScrolledWindow wrapping both line numbers and text
        scroll = Gtk.ScrolledWindow()
        scroll.set_hexpand(True)
        scroll.set_vexpand(True)

        # Inner box for line numbers + text side by side
        editor_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)

        self.line_nums = Gtk.TextView()
        self.line_nums.set_editable(False)
        self.line_nums.set_cursor_visible(False)
        self.line_nums.set_monospace(True)
        self.line_nums.set_size_request(50, -1)
        self.line_nums.add_css_class("editor-line-numbers")
        # Sync line number scroll with text scroll
        self.line_nums.set_wrap_mode(Gtk.WrapMode.NONE)
        editor_box.append(self.line_nums)

        self.text_view = Gtk.TextView()
        self.text_view.set_monospace(True)
        self.text_view.set_wrap_mode(Gtk.WrapMode.NONE)
        self.text_view.set_top_margin(4)
        self.text_view.set_left_margin(8)
        self.text_view.add_css_class("editor-text")
        self.text_view.set_hexpand(True)
        self.buffer = self.text_view.get_buffer()
        self.buffer.connect("changed", self._on_changed)
        editor_box.append(self.text_view)

        scroll.set_child(editor_box)
        ed.append(scroll)
        main.append(ed)

        # Sync scroll — line numbers follow text viewport
        scroll_vadj = scroll.get_vadjustment()
        self._line_scroll_signal = scroll_vadj.connect("value-changed", self._sync_line_scroll)

        # Status
        self.status = Gtk.Label(label="Ready")
        self.status.add_css_class("editor-status")
        self.status.set_xalign(0)
        main.append(self.status)

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self._on_key)
        self.add_controller(key)

        if filepath:
            self._open_file(filepath)

    def _sync_line_scroll(self, adj):
        """Sync line numbers scroll position with main text scroll."""
        self.line_nums.get_vadjustment().set_value(adj.get_value())

    def _push_undo(self):
        """Save current state to undo stack before modification."""
        start = self.buffer.get_start_iter()
        end = self.buffer.get_end_iter()
        text = self.buffer.get_text(start, end, False)
        self._undo_stack.append(text)
        if len(self._undo_stack) > 200:
            self._undo_stack.pop(0)
        self._redo_stack.clear()

    def _undo(self):
        if not self._undo_stack:
            return
        # Save current state to redo
        start = self.buffer.get_start_iter()
        end = self.buffer.get_end_iter()
        current = self.buffer.get_text(start, end, False)
        self._redo_stack.append(current)
        # Restore previous
        prev = self._undo_stack.pop()
        self.buffer.handler_block_by_func(self._on_changed)
        self.buffer.set_text(prev)
        self.buffer.handler_unblock_by_func(self._on_changed)
        self._update_lines()
        self.status.set_text("Undo")

    def _redo(self):
        if not self._redo_stack:
            return
        # Save current to undo
        start = self.buffer.get_start_iter()
        end = self.buffer.get_end_iter()
        current = self.buffer.get_text(start, end, False)
        self._undo_stack.append(current)
        # Restore redo state
        next_text = self._redo_stack.pop()
        self.buffer.handler_block_by_func(self._on_changed)
        self.buffer.set_text(next_text)
        self.buffer.handler_unblock_by_func(self._on_changed)
        self._update_lines()
        self.status.set_text("Redo")

    def _new(self):
        self._push_undo()
        self.buffer.set_text("")
        self.current_file = None
        self.modified = False
        self.set_title("Text Editor - Untitled")
        self._update_lines()

    def _open(self):
        d = Gtk.FileDialog()
        d.set_title("Open")
        d.open(self, None, self._on_opened)

    def _on_opened(self, d, r):
        try:
            f = d.open_finish(r)
            if f:
                self._open_file(f.get_path())
        except Exception:
            pass

    def _open_file(self, path):
        try:
            with open(path) as f:
                content = f.read()
            self._push_undo()
            self.buffer.set_text(content)
            self.current_file = path
            self.modified = False
            self.set_title(f"Text Editor - {os.path.basename(path)}")
            self._update_lines()
            self._detect_lang(path)
            self.status.set_text(f"Opened: {path}")
        except Exception as e:
            self.status.set_text(f"Error: {e}")

    def _save(self):
        if not self.current_file:
            d = Gtk.FileDialog()
            d.set_title("Save As")
            d.save(self, None, self._on_saved)
            return
        self._save_to(self.current_file)

    def _on_saved(self, d, r):
        try:
            f = d.save_finish(r)
            if f:
                self._save_to(f.get_path())
        except Exception:
            pass

    def _save_to(self, path):
        s = self.buffer.get_start_iter()
        e = self.buffer.get_end_iter()
        try:
            with open(path, "w") as f:
                f.write(self.buffer.get_text(s, e, False))
            self.current_file = path
            self.modified = False
            self.set_title(f"Text Editor - {os.path.basename(path)}")
            self.status.set_text(f"Saved: {path}")
        except Exception as ex:
            self.status.set_text(f"Error: {ex}")

    def _select_all(self):
        start = self.buffer.get_start_iter()
        end = self.buffer.get_end_iter()
        self.buffer.select_range(start, end)

    def _cut(self):
        self._push_undo()
        self.buffer.cut_clipboard(Gdk.Display.get_default().get_clipboard(), True)

    def _copy(self):
        self.buffer.copy_clipboard(Gdk.Display.get_default().get_clipboard())

    def _paste(self):
        self._push_undo()
        self.buffer.paste_clipboard(Gdk.Display.get_default().get_clipboard(), None, True)

    def _on_changed(self, _):
        self.modified = True
        t = self.get_title()
        if not t.startswith("●"):
            self.set_title(f"● {t}")
        self._update_lines()

    def _update_lines(self):
        n = self.buffer.get_line_count()
        self.line_nums.get_buffer().set_text(
            "\n".join(str(i) for i in range(1, n + 1))
        )

    def _detect_lang(self, path):
        ext = os.path.splitext(path)[1].lower()
        m = {
            ".py": "Python", ".js": "JavaScript", ".ts": "TypeScript",
            ".rs": "Rust", ".go": "Go", ".c": "C", ".h": "C Header",
            ".cpp": "C++", ".sh": "Shell", ".bash": "Bash",
            ".json": "JSON", ".md": "Markdown", ".html": "HTML",
            ".css": "CSS", ".yaml": "YAML", ".yml": "YAML",
            ".toml": "TOML", ".xml": "XML", ".sql": "SQL",
        }
        self.lang.set_text(m.get(ext, "Plain Text"))

    def _on_key(self, c, keyval, keycode, state):
        ctrl = state & Gdk.ModifierType.CONTROL_MASK
        if ctrl:
            if keyval == Gdk.KEY_s:
                self._save()
                return True
            if keyval == Gdk.KEY_n:
                self._new()
                return True
            if keyval == Gdk.KEY_o:
                self._open()
                return True
            if keyval == Gdk.KEY_z:
                self._undo()
                return True
            if keyval == Gdk.KEY_y:
                self._redo()
                return True
            if keyval == Gdk.KEY_a:
                self._select_all()
                return True
        return False
