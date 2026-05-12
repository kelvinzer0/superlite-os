"""File Manager - Lightweight file browser"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, Gio, GLib, Pango
import os
from pathlib import Path

_CSS_DONE = False

def _ensure_css():
    global _CSS_DONE
    if _CSS_DONE:
        return
    d = Gdk.Display.get_default()
    if not d:
        return
    _CSS_DONE = True
    css = b"""
    .fm-sidebar { background: #1a1a2e; border-right: 1px solid #16213e; padding: 8px; }
    .fm-sidebar-header { color: #e94560; font-weight: bold; font-size: 13px; padding: 8px; }
    .fm-bookmark-btn { background: transparent; color: #a0a0b0; border: none; text-align: left; padding: 6px 8px; border-radius: 4px; font-size: 12px; }
    .fm-bookmark-btn:hover { background: #16213e; color: #e0e0f0; }
    .fm-toolbar { background: #1a1a2e; padding: 4px 8px; border-bottom: 1px solid #16213e; }
    .fm-path-bar { background: #0f0f23; color: #e0e0f0; border: 1px solid #16213e; border-radius: 4px; padding: 4px 8px; font-family: monospace; font-size: 12px; }
    .fm-file-row { padding: 4px 8px; border-bottom: 1px solid #0a0a1a; }
    .fm-file-row:hover { background: #16213e; }
    .fm-dir-name { color: #4ecca3; font-weight: bold; }
    .fm-file-meta { color: #808090; font-size: 11px; }
    .fm-status { background: #1a1a2e; color: #808090; padding: 4px 8px; font-size: 11px; border-top: 1px solid #16213e; }
    """
    p = Gtk.CssProvider()
    p.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(d, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def _icon(name, is_dir):
    if is_dir: return "📁"
    ext = Path(name).suffix.lower()
    m = {".py":"🐍",".js":"📜",".md":"📝",".json":"📋",".png":"🖼️",".sh":"⚡",".txt":"📄",".zip":"📦"}
    return m.get(ext, "📄")


def _size(size, is_dir):
    if is_dir: return "<DIR>"
    for u in ["B","KB","MB","GB"]:
        if size < 1024: return f"{size:.0f}{u}" if u=="B" else f"{size:.1f}{u}"
        size /= 1024
    return f"{size:.1f}TB"


class FileManagerWindow(Gtk.Window):
    BOOKMARKS = [("🏠 Home","~"),("📁 Documents","~/Documents"),("📥 Downloads","~/Downloads"),("💾 /tmp","/tmp")]

    def __init__(self, path=None):
        super().__init__()
        self.set_title("Files")
        self.set_default_size(1000, 650)
        self.current_path = os.path.expanduser(path or "~")
        _ensure_css()

        main = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self.set_child(main)

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
        main.append(sb)

        # Content
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content.set_hexpand(True)
        main.append(content)

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
        content.append(tb)

        # File list
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        scroll.set_child(self.list_box)
        content.append(scroll)

        # Status
        self.status = Gtk.Label(label="")
        self.status.add_css_class("fm-status")
        self.status.set_xalign(0)
        content.append(self.status)

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
        g.connect("released", lambda _, n, x, y: self._on_click(name, full, is_dir, n))
        row.add_controller(g)
        self.list_box.append(row)

    def _on_click(self, name, full, is_dir, n):
        if n >= 2 and is_dir: self._navigate(full)

    def _go_back(self):
        self._navigate(os.path.dirname(self.current_path))

    def _go_up(self):
        self._go_back()
