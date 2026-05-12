"""Panel - Taskbar & System Tray"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Pango
from datetime import datetime
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:
    from ..wm import WindowManager


# Global CSS — loaded once via ensure_css()
_CSS_LOADED = False

def ensure_css():
    """Load CSS once. Call AFTER GTK display is ready."""
    global _CSS_LOADED
    if _CSS_LOADED:
        return
    display = Gdk.Display.get_default()
    if display is None:
        return
    _CSS_LOADED = True

    css = b"""
    .panel {
        background-color: #1a1a2e;
        border-bottom: 1px solid #16213e;
        padding: 0 8px;
    }
    .app-menu-btn {
        background: transparent;
        color: #e94560;
        font-weight: bold;
        border: none;
        padding: 0 12px;
    }
    .app-menu-btn:hover {
        background: #16213e;
    }
    .ws-btn {
        background: #16213e;
        color: #a0a0b0;
        border: 1px solid #0f3460;
        border-radius: 3px;
        min-width: 24px;
        padding: 2px 6px;
        font-size: 11px;
    }
    .ws-active {
        background: #e94560;
        color: white;
        border-color: #e94560;
    }
    .ws-has-windows {
        color: #e0e0f0;
    }
    .win-btn {
        background: #16213e;
        color: #a0a0b0;
        border: 1px solid #0f3460;
        border-radius: 3px;
        padding: 2px 10px;
        font-size: 11px;
    }
    .win-focused {
        background: #0f3460;
        color: white;
        border-color: #e94560;
    }
    .system-tray {
        color: #c0c0d0;
        font-size: 12px;
    }
    .clock {
        font-family: monospace;
    }
    """
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(
        display,
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )


class SystemTray(Gtk.Box):
    """System tray with clock, battery, volume indicators."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.add_css_class("system-tray")

        self.clock_label = Gtk.Label(label="")
        self.clock_label.add_css_class("clock")
        self.append(self.clock_label)

        self.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))

        self.battery_label = Gtk.Label(label="")
        self.battery_label.add_css_class("battery")
        self.append(self.battery_label)

        self.volume_label = Gtk.Label(label="🔊")
        self.volume_label.add_css_class("volume")
        self.append(self.volume_label)

        GLib.timeout_add_seconds(1, self._update_clock)
        self._update_clock()

        GLib.timeout_add_seconds(30, self._update_battery)
        self._update_battery()

    def _update_clock(self) -> bool:
        now = datetime.now()
        self.clock_label.set_text(now.strftime("%H:%M:%S  %d/%m/%Y"))
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
    """Taskbar showing open windows per workspace."""

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
        # Clear workspace buttons
        while self.ws_box.get_first_child():
            self.ws_box.remove(self.ws_box.get_first_child())

        for ws in self.wm.get_workspace_info():
            btn = Gtk.Button(label=str(ws["id"] + 1))
            btn.add_css_class("ws-btn")
            if ws["active"]:
                btn.add_css_class("ws-active")
            if ws["window_count"] > 0:
                btn.add_css_class("ws-has-windows")
            btn.connect("clicked", lambda b, wid=ws["id"]: self.wm._switch_workspace(wid))
            self.ws_box.append(btn)

        # Clear window buttons
        while self.win_box.get_first_child():
            self.win_box.remove(self.win_box.get_first_child())

        for win in self.wm.get_window_list():
            btn = Gtk.Button(label=win["title"][:30])
            btn.add_css_class("win-btn")
            if win["focused"]:
                btn.add_css_class("win-focused")
            self.win_box.append(btn)

        return True


class Panel(Gtk.Window):
    """Main panel bar at the top of the screen."""

    def __init__(self, wm: "WindowManager"):
        super().__init__()
        self.wm = wm
        self._launcher_callback: Callable = None

        self.set_title("SuperLite Panel")
        self.set_decorated(False)

        ensure_css()

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        box.set_size_request(-1, 36)
        box.add_css_class("panel")
        self.set_child(box)

        self.app_btn = Gtk.Button(label="⚡ SuperLite")
        self.app_btn.add_css_class("app-menu-btn")
        box.append(self.app_btn)

        self.taskbar = TaskBar(wm)
        self.taskbar.set_hexpand(True)
        box.append(self.taskbar)

    def set_launcher_callback(self, callback: Callable):
        """Connect app menu button to launcher."""
        self._launcher_callback = callback
        self.app_btn.connect("clicked", lambda b: callback())
