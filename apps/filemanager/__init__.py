"""File Manager - Lightweight two-pane file browser"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, Gio, GLib, Pango
import os
import shutil
from pathlib import Path
from datetime import datetime


class FileEntry:
    """Represents a file/directory entry."""
    def __init__(self, path: str):
        self.path = path
        self.name = os.path.basename(path)
        self.is_dir = os.path.isdir(path)
        try:
            stat = os.stat(path)
            self.size = stat.st_size
            self.modified = datetime.fromtimestamp(stat.st_mtime)
            self.permissions = oct(stat.st_mode)[-3:]
        except OSError:
            self.size = 0
            self.modified = datetime.now()
            self.permissions = "000"

    @property
    def icon(self) -> str:
        if self.is_dir:
            return "📁"
        ext = Path(self.name).suffix.lower()
        icons = {
            ".py": "🐍", ".js": "📜", ".ts": "📘", ".rs": "🦀",
            ".go": "🔵", ".c": "⚙️", ".cpp": "⚙️", ".h": "📋",
            ".txt": "📄", ".md": "📝", ".json": "📋", ".yaml": "📋",
            ".yml": "📋", ".toml": "📋", ".xml": "📋",
            ".png": "🖼️", ".jpg": "🖼️", ".jpeg": "🖼️", ".gif": "🖼️",
            ".svg": "🎨", ".webp": "🖼️",
            ".mp3": "🎵", ".wav": "🎵", ".flac": "🎵",
            ".mp4": "🎬", ".mkv": "🎬", ".avi": "🎬",
            ".zip": "📦", ".tar": "📦", ".gz": "📦", ".xz": "📦",
            ".deb": "📦", ".rpm": "📦",
            ".sh": "⚡", ".bash": "⚡",
            ".pdf": "📕", ".doc": "📘", ".docx": "📘",
        }
        return icons.get(ext, "📄")

    @property
    def size_str(self) -> str:
        if self.is_dir:
            return "<DIR>"
        for unit in ["B", "KB", "MB", "GB"]:
            if self.size < 1024:
                return f"{self.size:.0f}{unit}" if unit == "B" else f"{self.size:.1f}{unit}"
            self.size /= 1024
        return f"{self.size:.1f}TB"


class FileManagerWindow(Gtk.Window):
    """Two-pane file manager with navigation, bookmarks, and operations."""

    BOOKMARKS = [
        ("🏠 Home", "~"),
        ("📁 Documents", "~/Documents"),
        ("📥 Downloads", "~/Downloads"),
        ("🖼️ Pictures", "~/Pictures"),
        ("⚙️ /etc", "/etc"),
        ("🔧 /usr", "/usr"),
        ("💾 /tmp", "/tmp"),
    ]

    def __init__(self, path: str = None):
        super().__init__()
        self.set_title("Files")
        self.set_default_size(1000, 650)
        self.current_path = os.path.expanduser(path or "~")
        self.selected_files: set[str] = set()

        # Main layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        self.set_child(main_box)

        # Sidebar (bookmarks)
        self.sidebar = self._build_sidebar()
        main_box.append(self.sidebar)

        # Content area
        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        content_box.set_hexpand(True)
        main_box.append(content_box)

        # Toolbar
        toolbar = self._build_toolbar()
        content_box.append(toolbar)

        # File list
        self.file_list = self._build_file_list()
        content_box.append(self.file_list)

        # Status bar
        self.status_bar = Gtk.Label(label="")
        self.status_bar.add_css_class("fm-status")
        self.status_bar.set_xalign(0)
        content_box.append(self.status_bar)

        # Apply style
        self._apply_style()

        # Load initial path
        self._navigate(self.current_path)

    def _build_sidebar(self) -> Gtk.Box:
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        sidebar.add_css_class("fm-sidebar")
        sidebar.set_size_request(180, -1)

        # Header
        header = Gtk.Label(label="Bookmarks")
        header.add_css_class("fm-sidebar-header")
        sidebar.append(header)

        for name, path in self.BOOKMARKS:
            btn = Gtk.Button(label=name)
            btn.add_css_class("fm-bookmark-btn")
            resolved = os.path.expanduser(path)
            btn.connect("clicked", lambda b, p=resolved: self._navigate(p))
            sidebar.append(btn)

        # Spacer
        spacer = Gtk.Box()
        spacer.set_vexpand(True)
        sidebar.append(spacer)

        # Disk usage
        try:
            usage = shutil.disk_usage("/")
            used_pct = (usage.used / usage.total) * 100
            disk_label = Gtk.Label(label=f"💾 {used_pct:.0f}% used")
            disk_label.add_css_class("fm-disk-usage")
            sidebar.append(disk_label)
        except Exception:
            pass

        return sidebar

    def _build_toolbar(self) -> Gtk.Box:
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        toolbar.add_css_class("fm-toolbar")

        # Back button
        back_btn = Gtk.Button(label="◀")
        back_btn.set_tooltip_text("Back")
        back_btn.connect("clicked", lambda b: self._go_back())
        toolbar.append(back_btn)

        # Up button
        up_btn = Gtk.Button(label="▲")
        up_btn.set_tooltip_text("Up")
        up_btn.connect("clicked", lambda b: self._go_up())
        toolbar.append(up_btn)

        # Path bar
        self.path_entry = Gtk.Entry()
        self.path_entry.set_hexpand(True)
        self.path_entry.set_text(self.current_path)
        self.path_entry.add_css_class("fm-path-bar")
        self.path_entry.connect("activate", lambda e: self._navigate(e.get_text()))
        toolbar.append(self.path_entry)

        # New folder button
        new_folder_btn = Gtk.Button(label="📁+")
        new_folder_btn.set_tooltip_text("New folder")
        new_folder_btn.connect("clicked", lambda b: self._new_folder())
        toolbar.append(new_folder_btn)

        # Delete button
        del_btn = Gtk.Button(label="🗑️")
        del_btn.set_tooltip_text("Delete selected")
        del_btn.connect("clicked", lambda b: self._delete_selected())
        toolbar.append(del_btn)

        return toolbar

    def _build_file_list(self) -> Gtk.ScrolledWindow:
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)

        # Column headers
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header_box.add_css_class("fm-list-header")

        for text, width in [("Name", 350), ("Size", 80), ("Modified", 150), ("Perms", 60)]:
            label = Gtk.Label(label=text)
            label.set_size_request(width, -1)
            label.set_xalign(0)
            label.add_css_class("fm-header-label")
            header_box.append(label)

        # File list container
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.list_box.add_css_class("fm-file-list")

        container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        container.append(header_box)
        container.append(self.list_box)
        scroll.set_child(container)

        return scroll

    def _navigate(self, path: str):
        """Navigate to a directory."""
        path = os.path.abspath(path)
        if not os.path.isdir(path):
            return

        self.current_path = path
        self.path_entry.set_text(path)
        self.selected_files.clear()

        # Populate file list
        while self.list_box.get_first_child():
            self.list_box.remove(self.list_box.get_first_child())

        try:
            entries = sorted(
                [FileEntry(os.path.join(path, f)) for f in os.listdir(path)],
                key=lambda e: (not e.is_dir, e.name.lower()),
            )
        except PermissionError:
            self.status_bar.set_text("⚠️ Permission denied")
            return

        # Add parent directory entry
        parent = os.path.dirname(path)
        if parent != path:
            parent_entry = FileEntry(parent)
            parent_entry.name = ".."
            parent_entry.is_dir = True
            self._add_file_row(parent_entry, is_parent=True)

        for entry in entries:
            self._add_file_row(entry)

        self.status_bar.set_text(f"{len(entries)} items in {path}")

    def _add_file_row(self, entry: FileEntry, is_parent: bool = False):
        """Add a file entry row."""
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add_css_class("fm-file-row")

        # Icon + Name
        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name_box.set_size_request(350, -1)

        icon_label = Gtk.Label(label=entry.icon)
        name_box.append(icon_label)

        name_label = Gtk.Label(label=entry.name)
        name_label.set_xalign(0)
        name_label.set_ellipsize(Pango.EllipsizeMode.END)
        if entry.is_dir:
            name_label.add_css_class("fm-dir-name")
        name_box.append(name_label)
        row.append(name_box)

        # Size
        size_label = Gtk.Label(label=entry.size_str)
        size_label.set_size_request(80, -1)
        size_label.set_xalign(0)
        size_label.add_css_class("fm-file-meta")
        row.append(size_label)

        # Modified
        mod_label = Gtk.Label(label=entry.modified.strftime("%Y-%m-%d %H:%M"))
        mod_label.set_size_request(150, -1)
        mod_label.set_xalign(0)
        mod_label.add_css_class("fm-file-meta")
        row.append(mod_label)

        # Permissions
        perm_label = Gtk.Label(label=entry.permissions)
        perm_label.set_size_request(60, -1)
        perm_label.set_xalign(0)
        perm_label.add_css_class("fm-file-meta")
        row.append(perm_label)

        # Make clickable
        gesture = Gtk.GestureClick()
        gesture.connect("released", lambda g, n, x, y, p=entry: self._on_click(p))
        row.add_controller(gesture)

        # Double-click
        gesture.connect("released", lambda g, n, x, y, p=entry: self._on_double_click(p) if n >= 2 else None)

        self.list_box.append(row)

    def _on_click(self, entry: FileEntry):
        if entry.path in self.selected_files:
            self.selected_files.discard(entry.path)
        else:
            self.selected_files.add(entry.path)

    def _on_double_click(self, entry: FileEntry):
        if entry.is_dir:
            self._navigate(entry.path)
        else:
            # Open in text editor
            os.system(f"superlite-editor '{entry.path}' &")

    def _go_back(self):
        parent = os.path.dirname(self.current_path)
        self._navigate(parent)

    def _go_up(self):
        self._go_back()

    def _new_folder(self):
        dialog = Gtk.Dialog(title="New Folder", transient_for=self)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Create", Gtk.ResponseType.OK)

        entry = Gtk.Entry()
        entry.set_placeholder_text("Folder name")
        dialog.get_content_area().append(entry)
        dialog.present()

        def on_response(d, response):
            if response == Gtk.ResponseType.OK and entry.get_text():
                new_path = os.path.join(self.current_path, entry.get_text())
                try:
                    os.makedirs(new_path)
                    self._navigate(self.current_path)
                except Exception as e:
                    print(f"Error creating folder: {e}")
            d.close()

        dialog.connect("response", on_response)

    def _delete_selected(self):
        for path in list(self.selected_files):
            try:
                if os.path.isdir(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
            except Exception as e:
                print(f"Error deleting {path}: {e}")
        self.selected_files.clear()
        self._navigate(self.current_path)

    def _apply_style(self):
        css = b"""
        .fm-sidebar {
            background: #1a1a2e;
            border-right: 1px solid #16213e;
            padding: 8px;
        }
        .fm-sidebar-header {
            color: #e94560;
            font-weight: bold;
            font-size: 13px;
            padding: 8px;
        }
        .fm-bookmark-btn {
            background: transparent;
            color: #a0a0b0;
            border: none;
            text-align: left;
            padding: 6px 8px;
            border-radius: 4px;
            font-size: 12px;
        }
        .fm-bookmark-btn:hover {
            background: #16213e;
            color: #e0e0f0;
        }
        .fm-disk-usage {
            color: #808090;
            font-size: 11px;
        }
        .fm-toolbar {
            background: #1a1a2e;
            padding: 4px 8px;
            border-bottom: 1px solid #16213e;
        }
        .fm-path-bar {
            background: #0f0f23;
            color: #e0e0f0;
            border: 1px solid #16213e;
            border-radius: 4px;
            padding: 4px 8px;
            font-family: monospace;
            font-size: 12px;
        }
        .fm-list-header {
            background: #16213e;
            padding: 6px 8px;
            border-bottom: 1px solid #0f3460;
        }
        .fm-header-label {
            color: #808090;
            font-weight: bold;
            font-size: 11px;
        }
        .fm-file-row {
            padding: 4px 8px;
            border-bottom: 1px solid #0a0a1a;
        }
        .fm-file-row:hover {
            background: #16213e;
        }
        .fm-dir-name {
            color: #4ecca3;
            font-weight: bold;
        }
        .fm-file-meta {
            color: #808090;
            font-size: 11px;
        }
        .fm-status {
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
