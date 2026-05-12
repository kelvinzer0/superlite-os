"""App Launcher - dmenu-style application launcher overlay"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib
from dataclasses import dataclass
from typing import Callable, Optional


@dataclass
class AppEntry:
    name: str
    exec_cmd: str
    icon: str = "application-x-executable"
    description: str = ""
    category: str = "Other"


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

    css = b"""
    .launcher-overlay {
        background: rgba(0, 0, 0, 0.6);
    }
    .launcher {
        background: #1a1a2e;
        border: 2px solid #e94560;
        border-radius: 12px;
        padding: 16px;
    }
    .launcher-search {
        background: #16213e;
        color: #e0e0f0;
        border: 1px solid #0f3460;
        border-radius: 8px;
        padding: 12px 16px;
        font-size: 16px;
        caret-color: #e94560;
    }
    .launcher-item {
        background: transparent;
        border: none;
        border-radius: 6px;
        padding: 8px 12px;
        color: #e0e0f0;
    }
    .launcher-item:hover, .launcher-item-selected {
        background: #16213e;
    }
    .launcher-item-name {
        font-weight: bold;
        font-size: 14px;
    }
    .launcher-item-desc {
        font-size: 11px;
        color: #808090;
    }
    """
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(
        display,
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )


class AppLauncher(Gtk.Window):
    """Overlay-style application launcher with search."""

    def __init__(self, apps: Optional[list[AppEntry]] = None):
        super().__init__()
        self.apps = apps or self._default_apps()
        self.on_launch: Optional[Callable[[AppEntry], None]] = None

        self.set_title("Launcher")
        self.set_decorated(False)
        self.set_modal(True)
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
            return True
        elif keyval == Gdk.KEY_Up:
            self._selected_idx = max(self._selected_idx - 1, 0)
            self._update_selection()
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

    def _launch(self, app: AppEntry):
        if self.on_launch:
            self.on_launch(app)
        self.close()
