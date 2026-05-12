"""Terminal Emulator - PTY-based terminal"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Pango
import os
import subprocess
import threading
import pty
import select
import signal

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
    .terminal-window { background: #0f0f23; }
    .terminal-toolbar { background: #1a1a2e; padding: 4px 8px; border-bottom: 1px solid #16213e; }
    .terminal-output { background: #0f0f23; color: #e0e0f0; font-family: monospace; font-size: 13px; padding: 8px; }
    .terminal-input-bar { background: #1a1a2e; padding: 4px 8px; border-top: 1px solid #16213e; }
    .terminal-prompt { color: #4ecca3; font-weight: bold; font-family: monospace; }
    .terminal-input { background: #0f0f23; color: #e0e0f0; border: 1px solid #16213e; border-radius: 4px; padding: 4px 8px; font-family: monospace; caret-color: #e94560; }
    """
    p = Gtk.CssProvider()
    p.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(d, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


class TerminalWindow(Gtk.Window):
    def __init__(self, cwd: str = None):
        super().__init__()
        self.set_title("Terminal")
        self.set_default_size(800, 500)
        self.cwd = cwd or os.path.expanduser("~")
        self._pty_master = None
        self._child_pid = None

        _ensure_css()
        self.add_css_class("terminal-window")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(box)

        # Toolbar
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        toolbar.add_css_class("terminal-toolbar")
        cwd_label = Gtk.Label(label=f"📁 {self.cwd}")
        cwd_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        cwd_label.set_hexpand(True)
        cwd_label.set_xalign(0)
        toolbar.append(cwd_label)
        box.append(toolbar)

        # Output
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_hexpand(True)
        self.text_view = Gtk.TextView()
        self.text_view.set_editable(False)
        self.text_view.set_cursor_visible(False)
        self.text_view.set_monospace(True)
        self.text_view.set_wrap_mode(Gtk.WrapMode.CHAR)
        self.text_view.add_css_class("terminal-output")
        self.buffer = self.text_view.get_buffer()
        tag = self.buffer.create_tag("fg")
        tag.set_property("foreground", "#e0e0f0")
        scroll.set_child(self.text_view)
        box.append(scroll)

        # Input
        input_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        input_box.add_css_class("terminal-input-bar")
        prompt = Gtk.Label(label="$")
        prompt.add_css_class("terminal-prompt")
        self.input_entry = Gtk.Entry()
        self.input_entry.set_hexpand(True)
        self.input_entry.set_placeholder_text("Type command...")
        self.input_entry.add_css_class("terminal-input")
        self.input_entry.connect("activate", self._on_command)
        input_box.append(prompt)
        input_box.append(self.input_entry)
        box.append(input_box)

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect("key-pressed", self._on_key)
        self.add_controller(key_ctrl)

        self._start_shell()

    def _start_shell(self):
        shell = os.environ.get("SHELL", "/bin/bash")
        master, slave = pty.openpty()
        self._pty_master = master
        self._child_pid = os.fork()
        if self._child_pid == 0:
            os.close(master)
            os.setsid()
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.chdir(self.cwd)
            os.execvp(shell, [shell, "--login"])
        else:
            os.close(slave)
            threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        while True:
            try:
                r, _, _ = select.select([self._pty_master], [], [], 0.1)
                if r:
                    data = os.read(self._pty_master, 4096)
                    if data:
                        GLib.idle_add(self._append, data.decode("utf-8", errors="replace"))
            except (OSError, ValueError):
                break

    def _append(self, text):
        end = self.buffer.get_end_iter()
        self.buffer.insert_with_tags_by_name(end, text, "fg")
        self.text_view.scroll_mark_onscreen(self.buffer.get_insert())

    def _on_command(self, entry):
        cmd = entry.get_text()
        entry.set_text("")
        if cmd.strip() and self._pty_master:
            os.write(self._pty_master, (cmd + "\n").encode())

    def _on_key(self, c, keyval, keycode, state):
        if state & Gdk.ModifierType.CONTROL_MASK:
            if keyval == Gdk.KEY_c and self._child_pid:
                os.kill(self._child_pid, signal.SIGINT)
                return True
            if keyval == Gdk.KEY_l:
                self.buffer.set_text("")
                return True
        return False

    def close(self):
        if self._child_pid:
            try: os.kill(self._child_pid, signal.SIGTERM)
            except ProcessLookupError: pass
        if self._pty_master:
            try: os.close(self._pty_master)
            except OSError: pass
        super().close()
