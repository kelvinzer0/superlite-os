"""Session Manager - Main entry point for SuperLite OS desktop"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, Gio, GLib
import signal
import sys
import os
import subprocess
import json
from typing import Optional

# Robust imports — handle both `python -m core.session` and direct execution
try:
    from ..wm import WindowManager
    from ..panel import Panel, ensure_css as panel_css
    from ..launcher import AppLauncher, AppEntry, ensure_css as launcher_css
    from ..theme import get_theme, load_theme_from_config
except ImportError:
    # Fallback: add project root to sys.path
    _project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if _project_root not in sys.path:
        sys.path.insert(0, _project_root)
    from core.wm import WindowManager
    from core.panel import Panel, ensure_css as panel_css
    from core.launcher import AppLauncher, AppEntry, ensure_css as launcher_css
    from core.theme import get_theme, load_theme_from_config


def _load_keybindings() -> dict:
    """Load keybindings from config file."""
    config_path = os.path.expanduser("~/.config/superlite/config.json")
    try:
        with open(config_path) as f:
            config = json.load(f)
        return config.get("wm", {}).get("keybindings", {})
    except (OSError, json.JSONDecodeError):
        return {
            "launcher": "Super+Return",
            "close_window": "Super+q",
            "focus_next": "Super+j",
            "focus_prev": "Super+k",
            "toggle_maximize": "Super+f",
            "minimize": "Super+m",
            "toggle_floating": "Super+space",
            "switch_ws_1": "Super+1",
            "switch_ws_2": "Super+2",
            "switch_ws_3": "Super+3",
            "switch_ws_4": "Super+4",
            "terminal": "Super+Return",
            "file_manager": "Super+e",
            "text_editor": "Super+n",
            "browser": "Super+b",
        }


# Map keybinding names to Gdk keyval + modifier combos
def _parse_keybinding(binding: str) -> tuple[int, int]:
    """Parse a keybinding string like 'Super+Return' into (modifiers, keyval)."""
    parts = binding.split("+")
    mods = 0
    key_name = parts[-1]
    for mod in parts[:-1]:
        mod_lower = mod.strip().lower()
        if mod_lower in ("super", "mod4"):
            mods |= Gdk.ModifierType.SUPER_MASK
        elif mod_lower in ("ctrl", "control"):
            mods |= Gdk.ModifierType.CONTROL_MASK
        elif mod_lower == "alt":
            mods |= Gdk.ModifierType.ALT_MASK
        elif mod_lower == "shift":
            mods |= Gdk.ModifierType.SHIFT_MASK

    keyval = Gdk.keyval_from_name(key_name.lower())
    if keyval == 0:
        # Try common aliases
        aliases = {
            "return": Gdk.KEY_Return,
            "space": Gdk.KEY_space,
            "print": Gdk.KEY_Print,
        }
        keyval = aliases.get(key_name.lower(), 0)

    return mods, keyval


class Session:
    """
    Main session manager. Orchestrates:
    - Window Manager
    - Panel / Taskbar
    - App Launcher
    - Global keyboard shortcuts
    - Application lifecycle
    """

    def __init__(self):
        self.app = Gtk.Application(
            application_id="org.superlite.session",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self.app.connect("activate", self._on_activate)
        self.wm: Optional[WindowManager] = None
        self.panel: Optional[Panel] = None
        self.launcher: Optional[AppLauncher] = None
        self._child_processes: list[subprocess.Popen] = []
        self._keybindings: dict = {}

    def run(self, argv: list[str] = None):
        """Start the desktop session."""
        signal.signal(signal.SIGTERM, lambda *_: self._shutdown())
        signal.signal(signal.SIGINT, lambda *_: self._shutdown())

        os.environ.setdefault("XDG_CURRENT_DESKTOP", "SuperLite")
        os.environ.setdefault("DESKTOP_SESSION", "superlite")

        return self.app.run(argv or [])

    def _on_activate(self, app: Gtk.Application):
        """Initialize desktop when application activates."""
        # Load theme from config
        load_theme_from_config()

        # Pre-load all CSS
        panel_css()
        launcher_css()

        # Window Manager
        self.wm = WindowManager()

        # Panel
        self.panel = Panel(self.wm)
        self.panel.set_application(app)
        self.panel.present()

        # Launcher
        self.launcher = AppLauncher()
        self.launcher.on_launch = self._launch_app
        self.panel.set_launcher_callback(self._show_launcher)

        # Bind global keyboard shortcuts
        self._setup_keybindings(app)

        print("[SuperLite] Session started")

    def _setup_keybindings(self, app: Gtk.Application):
        """Set up global keyboard shortcuts from config."""
        self._keybindings = _load_keybindings()
        action_map = {
            "launcher": ("show-launcher", lambda: self._show_launcher()),
            "terminal": ("spawn-terminal", lambda: self._spawn_terminal()),
            "file_manager": ("spawn-filemanager", lambda: self._spawn_filemanager()),
            "text_editor": ("spawn-texteditor", lambda: self._spawn_texteditor()),
            "browser": ("spawn-browser", lambda: self._spawn_browser()),
            "close_window": ("close-window", lambda: self.wm.close_focused() if self.wm else None),
            "focus_next": ("focus-next", lambda: self.wm.focus_next() if self.wm else None),
            "focus_prev": ("focus-prev", lambda: self.wm.focus_prev() if self.wm else None),
            "toggle_maximize": ("toggle-maximize", lambda: self.wm.toggle_maximize_focused() if self.wm else None),
            "minimize": ("minimize", lambda: self.wm.minimize_focused() if self.wm else None),
            "toggle_floating": ("toggle-floating", lambda: self.wm.toggle_floating_focused() if self.wm else None),
            "switch_ws_1": ("switch-ws-1", lambda: self.wm._switch_workspace(0) if self.wm else None),
            "switch_ws_2": ("switch-ws-2", lambda: self.wm._switch_workspace(1) if self.wm else None),
            "switch_ws_3": ("switch-ws-3", lambda: self.wm._switch_workspace(2) if self.wm else None),
            "switch_ws_4": ("switch-ws-4", lambda: self.wm._switch_workspace(3) if self.wm else None),
        }

        accels = {}
        for binding_name, (action_name, callback) in action_map.items():
            binding_str = self._keybindings.get(binding_name)
            if not binding_str:
                continue

            action = Gio.SimpleAction.new(action_name, None)
            action.connect("activate", lambda _, __, cb=callback: cb())
            app.add_action(action)

            # Convert binding string to GTK accelerator format
            accel = binding_str.replace("Super", "<Super>").replace("+", "")
            # Normalize: "Super+Return" → "<Super>Return"
            parts = binding_str.split("+")
            accel_parts = []
            for p in parts[:-1]:
                p_lower = p.strip().lower()
                if p_lower in ("super", "mod4"):
                    accel_parts.append("<Super>")
                elif p_lower in ("ctrl", "control"):
                    accel_parts.append("<Ctrl>")
                elif p_lower == "alt":
                    accel_parts.append("<Alt>")
                elif p_lower == "shift":
                    accel_parts.append("<Shift>")
            accel_parts.append(parts[-1])
            accel = "".join(accel_parts)

            accels[action_name] = [accel]

        # Set accelerators on the application
        for action_name, accel_list in accels.items():
            app.set_accels_for_action(f"app.{action_name}", accel_list)

    def _show_launcher(self):
        """Show the app launcher overlay."""
        if self.launcher:
            self.launcher.set_transient_for(self.panel)
            self.launcher.present()

    def _launch_app(self, app: AppEntry):
        """Launch an application."""
        print(f"[SuperLite] Launching: {app.name} ({app.exec_cmd})")
        try:
            app_map = {
                "superlite-terminal": self._spawn_terminal,
                "superlite-files": self._spawn_filemanager,
                "superlite-editor": self._spawn_texteditor,
            }

            cmd_base = app.exec_cmd.split()[0]
            if cmd_base in app_map:
                app_map[cmd_base]()
            else:
                proc = subprocess.Popen(
                    app.exec_cmd.split(),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                self._child_processes.append(proc)
        except Exception as e:
            print(f"[SuperLite] Failed to launch {app.name}: {e}")

    def _spawn_terminal(self):
        try:
            from apps.terminal import TerminalWindow
        except ImportError:
            sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
            from apps.terminal import TerminalWindow
        win = TerminalWindow()
        win.set_application(self.app)
        self.wm.register_window(win, "terminal", "Terminal")
        win.present()

    def _spawn_filemanager(self):
        try:
            from apps.filemanager import FileManagerWindow
        except ImportError:
            sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
            from apps.filemanager import FileManagerWindow
        win = FileManagerWindow()
        win.set_application(self.app)
        self.wm.register_window(win, "filemanager", "Files")
        win.present()

    def _spawn_texteditor(self):
        try:
            from apps.texteditor import TextEditorWindow
        except ImportError:
            sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
            from apps.texteditor import TextEditorWindow
        win = TextEditorWindow()
        win.set_application(self.app)
        self.wm.register_window(win, "texteditor", "Text Editor")
        win.present()

    def _spawn_browser(self):
        try:
            from apps.browser import BrowserLauncher
        except ImportError:
            sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
            from apps.browser import BrowserLauncher
        launcher = BrowserLauncher()
        launcher.launch()

    def _shutdown(self):
        """Clean shutdown — kill all child processes."""
        print("[SuperLite] Shutting down...")

        # Kill tracked child processes
        for proc in self._child_processes:
            try:
                proc.terminate()
            except OSError:
                pass

        # Wait briefly, then force-kill
        import time
        time.sleep(0.5)
        for proc in self._child_processes:
            try:
                if proc.poll() is None:
                    proc.kill()
            except OSError:
                pass

        self._child_processes.clear()
        self.app.quit()
