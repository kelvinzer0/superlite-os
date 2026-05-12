"""App Launcher - dmenu-style application launcher overlay"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib
from dataclasses import dataclass
from typing import Callable, Optional
import os
import glob


@dataclass
class AppEntry:
    name: str
    exec_cmd: str
    icon: str = "application-x-executable"
    description: str = ""
    category: str = "Other"
    desktop_file: str = ""


# Launcher CSS — loaded once via ensure_css()
_LAUNCHER_CSS_LOADED = False

def ensure_css():
    """Load CSS once. Call AFTER GTK display is ready."""
    global _LAUNCHER_CSS_LOADED
    if _LAUNCHER_CSS_LOADED:
        return
    display = Gdk.Display.get_default()
    if display is None:
        return
    _LAUNCHER_CSS_LOADED = True

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
        @define-color sl-text-dim #808090;
        @define-color sl-text-bright #e0e0f0;
        @define-color sl-caret #e94560;
        """

    css = vars_css.encode() + b"""
    .launcher-overlay {
        background: rgba(0, 0, 0, 0.6);
    }
    .launcher {
        background: @sl-surface;
        border: 2px solid @sl-accent;
        border-radius: 12px;
        padding: 16px;
    }
    .launcher-search {
        background: @sl-surface-alt;
        color: @sl-text-bright;
        border: 1px solid @sl-border;
        border-radius: 8px;
        padding: 12px 16px;
        font-size: 16px;
        caret-color: @sl-caret;
    }
    .launcher-item {
        background: transparent;
        border: none;
        border-radius: 6px;
        padding: 8px 12px;
        color: @sl-text-bright;
    }
    .launcher-item:hover, .launcher-item-selected {
        background: @sl-surface-alt;
    }
    .launcher-item-name {
        font-weight: bold;
        font-size: 14px;
    }
    .launcher-item-desc {
        font-size: 11px;
        color: @sl-text-dim;
    }
    """
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(
        display,
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )


def _parse_desktop_file(path: str) -> Optional[AppEntry]:
    """Parse a .desktop file into an AppEntry."""
    try:
        data = {}
        in_desktop_entry = False
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line == "[Desktop Entry]":
                    in_desktop_entry = True
                    continue
                if line.startswith("["):
                    in_desktop_entry = False
                    continue
                if in_desktop_entry and "=" in line:
                    key, _, value = line.partition("=")
                    data[key.strip()] = value.strip()

        # Skip if NoDisplay or not an application
        if data.get("NoDisplay", "false").lower() == "true":
            return None
        if data.get("Type", "") != "Application":
            return None
        if "Name" not in data or "Exec" not in data:
            return None

        # Clean Exec: remove field codes %f %u %F %U etc.
        exec_cmd = data["Exec"]
        for code in ["%f", "%u", "%F", "%U", "%d", "%D", "%n", "%N", "%i", "%c", "%k", "%v", "%m"]:
            exec_cmd = exec_cmd.replace(code, "")
        exec_cmd = exec_cmd.strip()

        return AppEntry(
            name=data.get("Name", ""),
            exec_cmd=exec_cmd,
            icon=data.get("Icon", "application-x-executable"),
            description=data.get("Comment", data.get("GenericName", "")),
            category=data.get("Categories", "Other").split(";")[0] if data.get("Categories") else "Other",
            desktop_file=path,
        )
    except (OSError, KeyError, ValueError):
        return None


def scan_desktop_files() -> list[AppEntry]:
    """Scan XDG data dirs for .desktop files."""
    entries = []
    data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/share:/usr/local/share").split(":")
    data_dirs.append(os.path.expanduser("~/.local/share"))
    data_dirs.append("/usr/share")  # Ensure we always check this

    seen = set()
    for data_dir in data_dirs:
        pattern = os.path.join(data_dir, "applications", "*.desktop")
        for path in glob.glob(pattern):
            basename = os.path.basename(path)
            if basename in seen:
                continue
            seen.add(basename)
            entry = _parse_desktop_file(path)
            if entry:
                entries.append(entry)

    # Sort by name
    entries.sort(key=lambda e: e.name.lower())
    return entries


class AppLauncher(Gtk.Window):
    """Overlay-style application launcher with search."""

    def __init__(self, apps: Optional[list[AppEntry]] = None):
        super().__init__()
        self.apps = apps or self._load_apps()
        self.on_launch: Optional[Callable[[AppEntry], None]] = None

        self.set_title("Launcher")
        self.set_decorated(False)
        # Don't set modal — it blocks input to other windows and causes stacking issues
        self.set_default_size(600, 500)

        ensure_css()

        # Main container
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.add_css_class("launcher")
        box.set_margin_top(20)
        box.set_margin_bottom(20)
        box.set_margin_start(20)
        box.set_margin_end(20)
        self.set_child(box)

        # Search bar
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search applications...")
        self.search_entry.add_css_class("launcher-search")
        self.search_entry.connect("search-changed", self._on_search_changed)
        self.search_entry.connect("activate", self._on_activate)
        box.append(self.search_entry)

        # Scrolled results
        self.scrolled = Gtk.ScrolledWindow()
        self.scrolled.set_min_content_height(300)
        self.scrolled.set_vexpand(True)
        box.append(self.scrolled)

        # Results list
        self.results_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.scrolled.set_child(self.results_box)

        self._selected_idx = 0
        self._filtered: list[AppEntry] = []
        self._buttons: list[Gtk.Button] = []

        # Key controller
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect("key-pressed", self._on_key)
        self.add_controller(key_ctrl)

        # Initial display
        self._on_search_changed(self.search_entry)

    def _load_apps(self) -> list[AppEntry]:
        """Load apps — built-in first, then .desktop files."""
        builtins = self._default_apps()
        desktop_apps = scan_desktop_files()
        # Filter out desktop apps that duplicate built-in commands
        builtin_cmds = {a.exec_cmd.split()[0] for a in builtins}
        desktop_apps = [a for a in desktop_apps if a.exec_cmd.split()[0] not in builtin_cmds]
        return builtins + desktop_apps

    def _default_apps(self) -> list[AppEntry]:
        return [
            AppEntry("Terminal", "superlite-terminal", "utilities-terminal", "System terminal", "System"),
            AppEntry("Files", "superlite-files", "system-file-manager", "File manager", "System"),
            AppEntry("Text Editor", "superlite-editor", "accessories-text-editor", "Text editor", "Accessories"),
            AppEntry("Chrome", "google-chrome --no-sandbox", "google-chrome", "Chrome browser", "Internet"),
        ]

    def _on_search_changed(self, entry: Gtk.SearchEntry):
        query = entry.get_text().lower()
        self._filtered = [
            app for app in self.apps
            if query in app.name.lower() or query in app.description.lower()
        ] if query else list(self.apps)

        while self.results_box.get_first_child():
            self.results_box.remove(self.results_box.get_first_child())

        self._buttons = []
        for i, app in enumerate(self._filtered):
            btn = Gtk.Button()
            btn.add_css_class("launcher-item")

            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)

            icon = Gtk.Image.new_from_icon_name(app.icon)
            icon.set_pixel_size(32)
            row.append(icon)

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            name_label = Gtk.Label(label=app.name)
            name_label.set_xalign(0)
            name_label.add_css_class("launcher-item-name")
            text_box.append(name_label)

            desc_label = Gtk.Label(label=app.description)
            desc_label.set_xalign(0)
            desc_label.add_css_class("launcher-item-desc")
            text_box.append(desc_label)

            row.append(text_box)
            btn.set_child(row)
            btn.connect("clicked", lambda b, a=app: self._launch(a))

            self._buttons.append(btn)
            self.results_box.append(btn)

        self._selected_idx = 0
        self._update_selection()

    def _on_key(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        elif keyval == Gdk.KEY_Down:
            self._selected_idx = min(self._selected_idx + 1, len(self._buttons) - 1)
            self._update_selection()
            self._scroll_to_selected()
            return True
        elif keyval == Gdk.KEY_Up:
            self._selected_idx = max(self._selected_idx - 1, 0)
            self._update_selection()
            self._scroll_to_selected()
            return True
        elif keyval == Gdk.KEY_Return:
            if self._filtered:
                self._launch(self._filtered[self._selected_idx])
            return True
        return False

    def _on_activate(self, entry):
        if self._filtered:
            self._launch(self._filtered[self._selected_idx])

    def _update_selection(self):
        for i, btn in enumerate(self._buttons):
            if i == self._selected_idx:
                btn.add_css_class("launcher-item-selected")
                btn.grab_focus()
            else:
                btn.remove_css_class("launcher-item-selected")

    def _scroll_to_selected(self):
        """Scroll the results list so the selected item is visible."""
        if 0 <= self._selected_idx < len(self._buttons):
            btn = self._buttons[self._selected_idx]
            # Use GLib.idle_add to ensure the widget is allocated before scrolling
            GLib.idle_add(lambda: self._do_scroll(btn))

    def _do_scroll(self, btn: Gtk.Button) -> bool:
        """Actually scroll to the button's allocation."""
        try:
            adj = self.scrolled.get_vadjustment()
            alloc = btn.get_allocation()
            if alloc.height > 0:
                # Scroll so the button is centered in the viewport
                page_size = adj.get_page_size()
                target = alloc.y - (page_size - alloc.height) / 2
                adj.set_value(max(0, target))
        except Exception:
            pass
        return False  # Don't repeat

    def _launch(self, app: AppEntry):
        # Close launcher, then fire callback
        self.close()
        if self.on_launch:
            self.on_launch(app)
