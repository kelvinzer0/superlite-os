"""Panel - Taskbar & System Tray"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Pango
from datetime import datetime
from typing import TYPE_CHECKING, Callable, Optional

if TYPE_CHECKING:
    from ..wm import WindowManager

from ..theme import get_theme

_CSS_LOADED = False

def ensure_css():
    global _CSS_LOADED
    if _CSS_LOADED:
        return
    display = Gdk.Display.get_default()
    if display is None:
        return
    _CSS_LOADED = True
    t = get_theme()
    css = t.to_css_vars().encode() + b"""
    .panel { background-color: @sl-surface; border-bottom: 1px solid @sl-surface-alt; padding: 0 8px; }
    .app-menu-btn { background: transparent; color: @sl-accent; font-weight: bold; border: none; padding: 0 12px; }
    .app-menu-btn:hover { background: @sl-surface-alt; }
    .ws-btn { background: @sl-surface-alt; color: @sl-text-mid; border: 1px solid @sl-border; border-radius: 3px; min-width: 24px; padding: 2px 6px; font-size: 11px; }
    .ws-active { background: @sl-accent; color: white; border-color: @sl-accent; }
    .ws-has-windows { color: @sl-text-bright; }
    .win-btn { background: @sl-surface-alt; color: @sl-text-mid; border: 1px solid @sl-border; border-radius: 3px; padding: 2px 10px; font-size: 11px; }
    .win-focused { background: @sl-border; color: white; border-color: @sl-accent; }
    .system-tray { color: @sl-text-bright; font-size: 12px; }
    .clock { font-family: monospace; }
    """
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def _get_screen_width() -> int:
    try:
        d = Gdk.Display.get_default()
        if d:
            monitors = d.get_monitors()
            if monitors and monitors.get_n_items() > 0:
                return monitors.get_item(0).get_geometry().width
    except Exception:
        pass
    return 1280


class SystemTray(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.add_css_class("system-tray")
        self.clock_label = Gtk.Label(label="")
        self.clock_label.add_css_class("clock")
        self.append(self.clock_label)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        self.battery_label = Gtk.Label(label="")
        self.append(self.battery_label)
        self.volume_label = Gtk.Label(label="🔊")
        self.append(self.volume_label)
        GLib.timeout_add_seconds(1, self._update_clock)
        self._update_clock()
        GLib.timeout_add_seconds(30, self._update_battery)
        self._update_battery()

    def _update_clock(self) -> bool:
        self.clock_label.set_text(datetime.now().strftime("%H:%M:%S  %d/%m/%Y"))
        return True

    def _update_battery(self) -> bool:
        try:
            with open("/sys/class/power_supply/BAT0/capacity") as f:
                level = int(f.read().strip())
            with open("/sys/class/power_supply/BAT0/status") as f:
                status = f.read().strip()
            icon = "🔋" if status != "Charging" else "🔌"
            self.battery_label.set_text(f"{icon} {level}%")
        except FileNotFoundError:
            self.battery_label.set_text("")
        return True


class TaskBar(Gtk.Box):
    def __init__(self, wm: "WindowManager"):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.wm = wm
        self.add_css_class("taskbar")
        self.ws_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.append(self.ws_box)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        self.win_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        self.append(self.win_box)
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        self.append(spacer)
        self.tray = SystemTray()
        self.append(self.tray)
        GLib.timeout_add(500, self._refresh)

    def _refresh(self) -> bool:
        while self.ws_box.get_first_child():
            self.ws_box.remove(self.ws_box.get_first_child())
        for ws in self.wm.get_workspace_info():
            btn = Gtk.Button(label=str(ws["id"] + 1))
            btn.add_css_class("ws-btn")
            if ws["active"]: btn.add_css_class("ws-active")
            if ws["window_count"] > 0: btn.add_css_class("ws-has-windows")
            btn.connect("clicked", lambda b, wid=ws["id"]: self.wm._switch_workspace(wid))
            self.ws_box.append(btn)
        while self.win_box.get_first_child():
            self.win_box.remove(self.win_box.get_first_child())
        for win in self.wm.get_window_list():
            btn = Gtk.Button(label=win["title"][:30])
            btn.add_css_class("win-btn")
            if win["focused"]: btn.add_css_class("win-focused")
            self.win_box.append(btn)
        return True


class Panel(Gtk.Window):
    def __init__(self, wm: "WindowManager"):
        super().__init__()
        self.wm = wm
        self._launcher_callback: Optional[Callable] = None

        self.set_title("SuperLite Panel")
        self.set_decorated(False)

        # Set full screen width
        screen_w = _get_screen_width()
        self.set_default_size(screen_w, 36)

        ensure_css()

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        box.set_size_request(-1, 36)
        box.add_css_class("panel")
        self.set_child(box)

        self.app_btn = Gtk.Button(label="⚡ SuperLite")
        self.app_btn.add_css_class("app-menu-btn")
        self.app_btn.connect("clicked", self._on_app_btn_clicked)
        box.append(self.app_btn)

        self.taskbar = TaskBar(wm)
        self.taskbar.set_hexpand(True)
        box.append(self.taskbar)

        # Position at top of screen after realize
        self.connect("realize", self._on_realize)

    def _on_realize(self, win):
        """Move panel to top of screen after it's realized."""
        try:
            surface = self.get_surface()
            if surface:
                surface.set_position(0, 0)
        except Exception:
            pass

    def _on_app_btn_clicked(self, btn):
        if self._launcher_callback:
            self._launcher_callback()

    def set_launcher_callback(self, callback: Callable):
        self._launcher_callback = callback
