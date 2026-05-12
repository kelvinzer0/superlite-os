"""Session Manager - Main entry point for SuperLite OS desktop"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, Gio, GLib
import signal
import sys
import os
import subprocess
from typing import Optional

from ..wm import WindowManager
from ..panel import Panel, ensure_css as panel_css
from ..launcher import AppLauncher, AppEntry, ensure_css as launcher_css


class Session:
    """
    Main session manager. Orchestrates:
    - Window Manager
    - Panel / Taskbar
    - App Launcher
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

    def run(self, argv: list[str] = None):
        """Start the desktop session."""
        signal.signal(signal.SIGTERM, lambda *_: self._shutdown())
        signal.signal(signal.SIGINT, lambda *_: self._shutdown())

        os.environ.setdefault("XDG_CURRENT_DESKTOP", "SuperLite")
        os.environ.setdefault("DESKTOP_SESSION", "superlite")

        return self.app.run(argv or [])

    def _on_activate(self, app: Gtk.Application):
        """Initialize desktop when application activates."""
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

        print("[SuperLite] Session started")

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
                subprocess.Popen(
                    app.exec_cmd.split(),
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        except Exception as e:
            print(f"[SuperLite] Failed to launch {app.name}: {e}")

    def _spawn_terminal(self):
        from apps.terminal import TerminalWindow
        win = TerminalWindow()
        win.set_application(self.app)
        self.wm.register_window(win, "terminal", "Terminal")
        win.present()

    def _spawn_filemanager(self):
        from apps.filemanager import FileManagerWindow
        win = FileManagerWindow()
        win.set_application(self.app)
        self.wm.register_window(win, "filemanager", "Files")
        win.present()

    def _spawn_texteditor(self):
        from apps.texteditor import TextEditorWindow
        win = TextEditorWindow()
        win.set_application(self.app)
        self.wm.register_window(win, "texteditor", "Text Editor")
        win.present()

    def _shutdown(self):
        """Clean shutdown."""
        print("[SuperLite] Shutting down...")
        self.app.quit()
