"""Text Editor - Lightweight code editor with syntax awareness"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Pango
import os


class TextEditorWindow(Gtk.Window):
    """Simple but functional text editor with tabs, line numbers, and basic syntax support."""

    def __init__(self, filepath: str = None):
        super().__init__()
        self.set_title("Text Editor")
        self.set_default_size(900, 600)
        self.open_files: dict[str, str] = {}  # path -> content
        self.current_file: str = None
        self.modified: bool = False

        # Main layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(main_box)

        # Menu bar
        menu_bar = self._build_menu()
        main_box.append(menu_bar)

        # Toolbar
        toolbar = self._build_toolbar()
        main_box.append(toolbar)

        # Editor area (line numbers + text)
        editor_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        editor_box.set_vexpand(True)

        # Line numbers
        self.line_numbers = Gtk.TextView()
        self.line_numbers.set_editable(False)
        self.line_numbers.set_cursor_visible(False)
        self.line_numbers.set_monospace(True)
        self.line_numbers.set_size_request(50, -1)
        self.line_numbers.add_css_class("editor-line-numbers")
        editor_box.append(self.line_numbers)

        # Main text editor
        scroll = Gtk.ScrolledWindow()
        scroll.set_hexpand(True)
        scroll.set_vexpand(True)

        self.text_view = Gtk.TextView()
        self.text_view.set_monospace(True)
        self.text_view.set_wrap_mode(Gtk.WrapMode.NONE)
        self.text_view.set_top_margin(4)
        self.text_view.set_left_margin(8)
        self.text_view.add_css_class("editor-text")

        self.buffer = self.text_view.get_buffer()
        self.buffer.connect("changed", self._on_text_changed)

        scroll.set_child(self.text_view)
        editor_box.append(scroll)

        main_box.append(editor_box)

        # Status bar
        self.status_bar = Gtk.Label(label="Ready")
        self.status_bar.add_css_class("editor-status")
        self.status_bar.set_xalign(0)
        main_box.append(self.status_bar)

        # Apply style
        self._apply_style()

        # Key bindings
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect("key-pressed", self._on_key)
        self.add_controller(key_ctrl)

        # Load file if provided
        if filepath:
            self._open_file(filepath)

    def _build_menu(self) -> Gtk.Box:
        menu = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        menu.add_css_class("editor-menu")

        menus = {
            "File": [
                ("New", "<Ctrl>n", self._new_file),
                ("Open", "<Ctrl>o", self._open_dialog),
                ("Save", "<Ctrl>s", self._save_file),
                ("Save As", "<Ctrl><Shift>s", self._save_as_dialog),
                ("Quit", "<Ctrl>q", lambda: self.close()),
            ],
            "Edit": [
                ("Undo", "<Ctrl>z", self._undo),
                ("Redo", "<Ctrl>y", self._redo),
                ("Cut", "<Ctrl>x", self._cut),
                ("Copy", "<Ctrl>c", self._copy),
                ("Paste", "<Ctrl>v", self._paste),
                ("Select All", "<Ctrl>a", self._select_all),
                ("Find", "<Ctrl>f", self._show_find),
            ],
            "View": [
                ("Line Numbers", None, self._toggle_line_numbers),
                ("Word Wrap", None, self._toggle_word_wrap),
            ],
        }

        for label, items in menus.items():
            btn = Gtk.MenuButton(label=label)
            btn.add_css_class("editor-menu-btn")

            menu_model = Gio.Menu()
            for item_label, accel, callback in items:
                action = Gio.SimpleAction.new(item_label.lower().replace(" ", "_"), None)
                action.connect("activate", lambda a, p, cb=callback: cb())
                self.add_action(action)
                menu_model.append(item_label, f"win.{item_label.lower().replace(' ', '_')}")

            btn.set_menu_model(menu_model)
            menu.append(btn)

        return menu

    def _build_toolbar(self) -> Gtk.Box:
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        toolbar.add_css_class("editor-toolbar")

        for label, tooltip, callback in [
            ("📄", "New", self._new_file),
            ("📂", "Open", self._open_dialog),
            ("💾", "Save", self._save_file),
            ("↩", "Undo", self._undo),
            ("↪", "Redo", self._redo),
            ("🔍", "Find", self._show_find),
        ]:
            btn = Gtk.Button(label=label)
            btn.set_tooltip_text(tooltip)
            btn.add_css_class("editor-tool-btn")
            btn.connect("clicked", lambda b, cb=callback: cb())
            toolbar.append(btn)

        # Spacer
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        toolbar.append(spacer)

        # Language/filetype indicator
        self.lang_label = Gtk.Label(label="Plain Text")
        self.lang_label.add_css_class("editor-lang-label")
        toolbar.append(self.lang_label)

        return toolbar

    def _new_file(self):
        self.buffer.set_text("")
        self.current_file = None
        self.modified = False
        self.set_title("Text Editor - Untitled")
        self._update_line_numbers()

    def _open_dialog(self):
        dialog = Gtk.FileDialog()
        dialog.set_title("Open File")
        dialog.open(self, None, self._on_file_opened)

    def _on_file_opened(self, dialog, result):
        try:
            file = dialog.open_finish(result)
            if file:
                self._open_file(file.get_path())
        except Exception:
            pass

    def _open_file(self, path: str):
        try:
            with open(path, "r") as f:
                content = f.read()
            self.buffer.set_text(content)
            self.current_file = path
            self.modified = False
            self.set_title(f"Text Editor - {os.path.basename(path)}")
            self._update_line_numbers()
            self._detect_language(path)
        except Exception as e:
            self.status_bar.set_text(f"Error: {e}")

    def _save_file(self):
        if not self.current_file:
            self._save_as_dialog()
            return
        self._save_to(self.current_file)

    def _save_as_dialog(self):
        dialog = Gtk.FileDialog()
        dialog.set_title("Save As")
        dialog.save(self, None, self._on_file_saved)

    def _on_file_saved(self, dialog, result):
        try:
            file = dialog.save_finish(result)
            if file:
                self._save_to(file.get_path())
        except Exception:
            pass

    def _save_to(self, path: str):
        start = self.buffer.get_start_iter()
        end = self.buffer.get_end_iter()
        text = self.buffer.get_text(start, end, False)
        try:
            with open(path, "w") as f:
                f.write(text)
            self.current_file = path
            self.modified = False
            self.set_title(f"Text Editor - {os.path.basename(path)}")
            self.status_bar.set_text(f"Saved: {path}")
        except Exception as e:
            self.status_bar.set_text(f"Error saving: {e}")

    def _undo(self):
        # GTK4 TextView doesn't have built-in undo, would need custom implementation
        pass

    def _redo(self):
        pass

    def _cut(self):
        clipboard = Gdk.Display.get_default().get_clipboard()
        self.buffer.cut_clipboard(clipboard, True)

    def _copy(self):
        clipboard = Gdk.Display.get_default().get_clipboard()
        self.buffer.copy_clipboard(clipboard)

    def _paste(self):
        clipboard = Gdk.Display.get_default().get_clipboard()
        self.buffer.paste_clipboard(clipboard, None, True)

    def _select_all(self):
        start = self.buffer.get_start_iter()
        end = self.buffer.get_end_iter()
        self.buffer.select_range(start, end)

    def _show_find(self):
        # Simple find bar
        self.status_bar.set_text("Find: (implement search bar)")
        pass

    def _toggle_line_numbers(self):
        self.line_numbers.set_visible(not self.line_numbers.get_visible())

    def _toggle_word_wrap(self):
        if self.text_view.get_wrap_mode() == Gtk.WrapMode.NONE:
            self.text_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        else:
            self.text_view.set_wrap_mode(Gtk.WrapMode.NONE)

    def _on_text_changed(self, buffer):
        self.modified = True
        title = self.get_title()
        if not title.startswith("●"):
            self.set_title(f"● {title}")
        self._update_line_numbers()
        self._update_cursor_pos()

    def _update_line_numbers(self):
        line_count = self.buffer.get_line_count()
        text = "\n".join(str(i) for i in range(1, line_count + 1))
        buf = self.line_numbers.get_buffer()
        buf.set_text(text)

    def _update_cursor_pos(self):
        cursor = self.buffer.get_insert()
        iter = self.buffer.get_iter_at_mark(cursor)
        line = iter.get_line() + 1
        col = iter.get_line_offset() + 1
        self.status_bar.set_text(f"Ln {line}, Col {col}")

    def _detect_language(self, path: str):
        ext = os.path.splitext(path)[1].lower()
        lang_map = {
            ".py": "Python", ".js": "JavaScript", ".ts": "TypeScript",
            ".rs": "Rust", ".go": "Go", ".c": "C", ".cpp": "C++",
            ".h": "C Header", ".java": "Java", ".rb": "Ruby",
            ".sh": "Shell", ".bash": "Bash", ".html": "HTML",
            ".css": "CSS", ".json": "JSON", ".yaml": "YAML",
            ".yml": "YAML", ".toml": "TOML", ".xml": "XML",
            ".md": "Markdown", ".txt": "Plain Text",
        }
        self.lang_label.set_text(lang_map.get(ext, "Plain Text"))

    def _on_key(self, controller, keyval, keycode, state):
        ctrl = state & Gdk.ModifierType.CONTROL_MASK
        if ctrl and keyval == Gdk.KEY_s:
            self._save_file()
            return True
        elif ctrl and keyval == Gdk.KEY_n:
            self._new_file()
            return True
        elif ctrl and keyval == Gdk.KEY_o:
            self._open_dialog()
            return True
        elif ctrl and keyval == Gdk.KEY_q:
            self.close()
            return True
        return False

    def _apply_style(self):
        css = b"""
        .editor-menu {
            background: #1a1a2e;
            padding: 2px 4px;
            border-bottom: 1px solid #16213e;
        }
        .editor-menu-btn {
            background: transparent;
            color: #a0a0b0;
            border: none;
            padding: 4px 10px;
        }
        .editor-menu-btn:hover {
            background: #16213e;
            color: #e0e0f0;
        }
        .editor-toolbar {
            background: #16213e;
            padding: 4px 8px;
            border-bottom: 1px solid #0f3460;
        }
        .editor-tool-btn {
            background: transparent;
            color: #a0a0b0;
            border: 1px solid #0f3460;
            border-radius: 3px;
            padding: 2px 8px;
            font-size: 14px;
        }
        .editor-tool-btn:hover {
            background: #0f3460;
            color: #e0e0f0;
        }
        .editor-lang-label {
            color: #e94560;
            font-size: 11px;
            font-weight: bold;
        }
        .editor-line-numbers {
            background: #0f0f23;
            color: #505060;
            font-size: 12px;
            padding: 4px;
            border-right: 1px solid #16213e;
        }
        .editor-text {
            background: #0f0f23;
            color: #e0e0f0;
            font-size: 13px;
            caret-color: #e94560;
        }
        .editor-status {
            background: #1a1a2e;
            color: #808090;
            padding: 4px 8px;
            font-size: 11px;
            border-top: 1px solid #16213e;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )
