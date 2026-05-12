"""File Manager - Lightweight file browser"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, Gio, GLib, Pango
import os
import sys
import subprocess
from pathlib import Path

try:
    from core.decorations import apply_titlebar
except ImportError:
    _root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if _root not in sys.path:
        sys.path.insert(0, _root)
    from core.decorations import apply_titlebar

_CSS_DONE = False

def _ensure_css():
    global _CSS_DONE
    if _CSS_DONE:
        return
    d = Gdk.Display.get_default()
    if not d:
        return
    _CSS_DONE = True
    try:
        from core.theme import get_theme
        t = get_theme()
        vars_css = t.to_css_vars()
    except ImportError:
        vars_css = """
        @define-color sl-bg #0f0f23;
        @define-color sl-fg #e0e0f0;
        @define-color sl-accent #e94560;
        @define-color sl-surface #1a1a2e;
        @define-color sl-surface-alt #16213e;
        @define-color sl-border #0f3460;
        @define-color sl-success #4ecca3;
        @define-color sl-text-dim #808090;
        @define-color sl-text-bright #e0e0f0;
        @define-color sl-error #e94560;
        """
    css = vars_css.encode() + b"""
    .fm-sidebar { background: @sl-surface; border-right: 1px solid @sl-surface-alt; padding: 8px; }
    .fm-sidebar-header { color: @sl-accent; font-weight: bold; font-size: 13px; padding: 8px; }
    .fm-bookmark-btn { background: transparent; color: @sl-text-dim; border: none; text-align: left; padding: 6px 8px; border-radius: 4px; font-size: 12px; }
    .fm-bookmark-btn:hover { background: @sl-surface-alt; color: @sl-text-bright; }
    .fm-toolbar { background: @sl-surface; padding: 4px 8px; border-bottom: 1px solid @sl-surface-alt; }
    .fm-path-bar { background: @sl-bg; color: @sl-text-bright; border: 1px solid @sl-surface-alt; border-radius: 4px; padding: 4px 8px; font-family: monospace; font-size: 12px; }
    .fm-file-row { padding: 4px 8px; border-bottom: 1px solid @sl-bg; }
    .fm-file-row:hover { background: @sl-surface-alt; }
    .fm-dir-name { color: @sl-success; font-weight: bold; }
    .fm-file-meta { color: @sl-text-dim; font-size: 11px; }
    .fm-status { background: @sl-surface; color: @sl-text-dim; padding: 4px 8px; font-size: 11px; border-top: 1px solid @sl-surface-alt; }
    """
    p = Gtk.CssProvider()
    p.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(d, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def _icon(name, is_dir):
    if is_dir: return "📁"
    ext = Path(name).suffix.lower()
    m = {".py":"🐍",".js":"📜",".md":"📝",".json":"📋",".png":"🖼️",".sh":"⚡",".txt":"📄",".zip":"📦",
         ".jpg":"🖼️",".jpeg":"🖼️",".gif":"🖼️",".svg":"🖼️",".pdf":"📕",".html":"🌐",".css":"🎨"}
    return m.get(ext, "📄")


def _size(size, is_dir):
    if is_dir: return "<DIR>"
    for u in ["B","KB","MB","GB"]:
        if size < 1024: return f"{size:.0f}{u}" if u=="B" else f"{size:.1f}{u}"
        size /= 1024
    return f"{size:.1f}TB"


def _open_file_with_default(filepath: str):
    ext = os.path.splitext(filepath)[1].lower()
    text_exts = {".py",".js",".ts",".md",".txt",".json",".yaml",".yml",".toml",".cfg",".ini",".conf",".sh",".bash",".c",".h",".cpp",".rs",".go",".html",".css",".xml",".csv",".log"}
    if ext in text_exts:
        subprocess.Popen(["superlite-editor", filepath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    for cmd in [["xdg-open", filepath], ["gio", "open", filepath]]:
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        except FileNotFoundError:
            continue


class FileManagerWindow(Gtk.Window):
    BOOKMARKS = [("🏠 Home","~"),("📁 Documents","~/Documents"),("📥 Downloads","~/Downloads"),("💾 /tmp","/tmp")]

    def __init__(self, path=None):
        super().__init__()
        self.set_title("Files")
        self.set_default_size(1000, 650)
        self.current_path = os.path.expanduser(path or "~")
        self.show_hidden = False
        _ensure_css()

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(main)

        # Header
        header = apply_titlebar(self, icon="📁", title="Files")
        main.append(header)

        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        body.set_vexpand(True)
        main.append(body)

        # Sidebar
        sb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        sb.add_css_class("fm-sidebar")
        sb.set_size_request(180, -1)
        h = Gtk.Label(label="Bookmarks")
        h.add_css_class("fm-sidebar-header")
        sb.append(h)
        for n, p in self.BOOKMARKS:
            b = Gtk.Button(label=n)
            b.add_css_class("fm-bookmark-btn")
            r = os.path.expanduser(p)
            b.connect("clicked", lambda _, pp=r: self._navigate(pp))
            sb.append(b)
        sp = Gtk.Box(); sp.set_vexpand(True); sb.append(sp)
        body.append(sb)

        # Content
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content.set_hexpand(True)
        body.append(content)

        # Toolbar
        tb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        tb.add_css_class("fm-toolbar")
        bb = Gtk.Button(label="◀"); bb.connect("clicked", lambda _: self._go_back()); tb.append(bb)
        ub = Gtk.Button(label="▲"); ub.connect("clicked", lambda _: self._go_up()); tb.append(ub)
        self.path_entry = Gtk.Entry()
        self.path_entry.set_hexpand(True)
        self.path_entry.set_text(self.current_path)
        self.path_entry.add_css_class("fm-path-bar")
        self.path_entry.connect("activate", lambda e: self._navigate(e.get_text()))
        tb.append(self.path_entry)
        self.hidden_btn = Gtk.Button(label="👁")
        self.hidden_btn.set_tooltip_text("Toggle hidden files")
        self.hidden_btn.connect("clicked", lambda _: self._toggle_hidden())
        tb.append(self.hidden_btn)
        content.append(tb)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        scroll.set_child(self.list_box)
        content.append(scroll)

        self.status = Gtk.Label(label="")
        self.status.add_css_class("fm-status")
        self.status.set_xalign(0)
        content.append(self.status)

        self._navigate(self.current_path)

    def _toggle_hidden(self):
        self.show_hidden = not self.show_hidden
        self._navigate(self.current_path)

    def _navigate(self, path):
        path = os.path.abspath(path)
        if not os.path.isdir(path): return
        self.current_path = path
        self.path_entry.set_text(path)
        while self.list_box.get_first_child():
            self.list_box.remove(self.list_box.get_first_child())
        try:
            entries = sorted(
                [(f, os.path.join(path, f)) for f in os.listdir(path)],
                key=lambda x: (not os.path.isdir(x[1]), x[0].lower()))
        except PermissionError:
            self.status.set_text("⚠️ Permission denied")
            return
        if not self.show_hidden:
            entries = [(n, f) for n, f in entries if not n.startswith(".")]
        parent = os.path.dirname(path)
        if parent != path:
            self._add_row("..", parent, True)
        for name, full in entries:
            self._add_row(name, full, os.path.isdir(full))
        self.status.set_text(f"{len(entries)} items in {path}")

    def _add_row(self, name, full, is_dir):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add_css_class("fm-file-row")
        row.append(Gtk.Label(label=_icon(name, is_dir)))
        nl = Gtk.Label(label=name)
        nl.set_xalign(0); nl.set_hexpand(True); nl.set_ellipsize(Pango.EllipsizeMode.END)
        if is_dir: nl.add_css_class("fm-dir-name")
        row.append(nl)
        try:
            s = os.stat(full)
            sl = Gtk.Label(label=_size(s.st_size, is_dir))
            sl.set_xalign(0); sl.add_css_class("fm-file-meta"); row.append(sl)
        except OSError: pass
        g = Gtk.GestureClick()
        g.connect("released", lambda _, n, x, y, nm=name, fp=full, d=is_dir: self._on_click(nm, fp, d, n))
        row.add_controller(g)
        rc = Gtk.GestureClick()
        rc.set_button(3)
        rc.connect("released", lambda _, n, x, y, nm=name, fp=full, d=is_dir: self._show_context_menu(nm, fp, d, x, y))
        row.add_controller(rc)
        self.list_box.append(row)

    def _on_click(self, name, full, is_dir, n):
        if n >= 2:
            if is_dir: self._navigate(full)
            else: _open_file_with_default(full)

    def _show_context_menu(self, name, full, is_dir, x, y):
        popover = Gtk.Popover()
        menu_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        menu_box.set_margin_top(4); menu_box.set_margin_bottom(4); menu_box.set_margin_start(4); menu_box.set_margin_end(4)
        open_btn = Gtk.Button(label="📂 Open")
        open_btn.connect("clicked", lambda _: (self._navigate(full) if is_dir else _open_file_with_default(full), popover.popdown()))
        menu_box.append(open_btn)
        rename_btn = Gtk.Button(label="✏️ Rename")
        rename_btn.connect("clicked", lambda _: (self._rename_file(name, full), popover.popdown()))
        menu_box.append(rename_btn)
        del_btn = Gtk.Button(label="🗑️ Delete")
        del_btn.connect("clicked", lambda _: (self._delete_file(name, full), popover.popdown()))
        menu_box.append(del_btn)
        popover.set_child(menu_box)
        popover.set_parent(self.list_box)
        rect = Gdk.Rectangle(); rect.x = int(x); rect.y = int(y); rect.width = 1; rect.height = 1
        popover.set_pointing_to(rect)
        popover.popup()

    def _rename_file(self, name, full):
        dialog = Gtk.Window(title=f"Rename: {name}", modal=True, transient_for=self, default_width=350, default_height=100)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        box.append(Gtk.Label(label=f"Rename '{name}' to:"))
        entry = Gtk.Entry(text=name)
        box.append(entry)
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, halign=Gtk.Align.END)
        cancel = Gtk.Button(label="Cancel"); cancel.connect("clicked", lambda _: dialog.close()); btn_box.append(cancel)
        ok = Gtk.Button(label="Rename"); ok.connect("clicked", lambda _: self._do_rename(full, entry.get_text(), dialog)); btn_box.append(ok)
        box.append(btn_box)
        dialog.set_child(box)
        entry.connect("activate", lambda _: self._do_rename(full, entry.get_text(), dialog))
        dialog.present()

    def _do_rename(self, old, new_name, dialog):
        if not new_name or new_name == os.path.basename(old): dialog.close(); return
        try:
            os.rename(old, os.path.join(os.path.dirname(old), new_name))
            dialog.close(); self._navigate(self.current_path)
        except OSError as e:
            self.status.set_text(f"Error: {e}"); dialog.close()

    def _delete_file(self, name, full):
        dialog = Gtk.Window(title="Confirm Delete", modal=True, transient_for=self, default_width=350, default_height=100)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin_top=12, margin_bottom=12, margin_start=12, margin_end=12)
        box.append(Gtk.Label(label=f"Delete '{name}'?"))
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, halign=Gtk.Align.END)
        cancel = Gtk.Button(label="Cancel"); cancel.connect("clicked", lambda _: dialog.close()); btn_box.append(cancel)
        ok = Gtk.Button(label="Delete"); ok.connect("clicked", lambda _: self._do_delete(full, dialog)); btn_box.append(ok)
        box.append(btn_box)
        dialog.set_child(box)
        dialog.present()

    def _do_delete(self, path, dialog):
        try:
            import shutil
            if os.path.isdir(path): shutil.rmtree(path)
            else: os.remove(path)
            dialog.close(); self._navigate(self.current_path)
        except OSError as e:
            self.status.set_text(f"Error: {e}"); dialog.close()

    def _go_back(self): self._navigate(os.path.dirname(self.current_path))
    def _go_up(self): self._go_back()
