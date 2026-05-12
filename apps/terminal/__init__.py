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
import struct
import fcntl
import sys

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
        @define-color sl-surface #1a1a2e;
        @define-color sl-surface-alt #16213e;
        @define-color sl-text-bright #e0e0f0;
        @define-color sl-success #4ecca3;
        @define-color sl-caret #e94560;
        @define-color sl-text-dim #808090;
        """
    css = vars_css.encode() + b"""
    .terminal-window { background: @sl-bg; }
    .terminal-output { background: @sl-bg; color: @sl-text-bright; font-family: monospace; font-size: 13px; padding: 8px; }
    .terminal-input-bar { background: @sl-surface; padding: 4px 8px; border-top: 1px solid @sl-surface-alt; }
    .terminal-prompt { color: @sl-success; font-weight: bold; font-family: monospace; }
    .terminal-input { background: @sl-bg; color: @sl-text-bright; border: 1px solid @sl-surface-alt; border-radius: 4px; padding: 4px 8px; font-family: monospace; caret-color: @sl-caret; }
    """
    p = Gtk.CssProvider()
    p.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(d, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


_TIOCSWINSZ = 0x5414


class TerminalWindow(Gtk.Window):
    def __init__(self, cwd: str = None):
        super().__init__()
        self.set_title("Terminal")
        self.set_default_size(800, 500)
        self.cwd = cwd or os.path.expanduser("~")
        self._pty_master = None
        self._child_pid = None
        self._reader_running = False
        self._reader_thread = None
        self._closing = False

        _ensure_css()
        self.add_css_class("terminal-window")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(box)

        # Header bar (inside content, not replacing native titlebar)
        header = apply_titlebar(self, icon="🖥️", title="Terminal")
        box.append(header)

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
        self.buffer.create_tag("fg").set_property("foreground", "#e0e0f0")
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

        self.connect("notify::default-width", self._on_resize)
        self.connect("notify::default-height", self._on_resize)
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
            if slave > 2:
                os.close(slave)
            os.chdir(self.cwd)
            os.execvp(shell, [shell, "--login"])
        else:
            os.close(slave)
            self._reader_running = True
            self._reader_thread = threading.Thread(target=self._reader, daemon=True)
            self._reader_thread.start()

    def _reader(self):
        while self._reader_running and self._pty_master is not None:
            try:
                r, _, _ = select.select([self._pty_master], [], [], 0.1)
                if r:
                    data = os.read(self._pty_master, 4096)
                    if not data:
                        break
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
        if cmd.strip() and self._pty_master is not None:
            try:
                os.write(self._pty_master, (cmd + "\n").encode())
            except OSError:
                pass

    def _on_key(self, c, keyval, keycode, state):
        if state & Gdk.ModifierType.CONTROL_MASK:
            if keyval == Gdk.KEY_c and self._child_pid:
                try:
                    os.kill(self._child_pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
                return True
            if keyval == Gdk.KEY_l:
                self.buffer.set_text("")
                return True
        return False

    def _on_resize(self, *args):
        if self._child_pid and self._pty_master:
            try:
                w, h = self.get_width(), self.get_height()
                cols, rows = max(1, w // 8), max(1, h // 16)
                fcntl.ioctl(self._pty_master, _TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
                os.kill(self._child_pid, signal.SIGWINCH)
            except (OSError, ProcessLookupError):
                pass

    def close(self):
        if self._closing:
            return
        self._closing = True
        self._reader_running = False
        if self._reader_thread and self._reader_thread.is_alive():
            self._reader_thread.join(timeout=1.0)
        if self._child_pid:
            try:
                os.kill(self._child_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                os.kill(self._child_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self._child_pid = None
        if self._pty_master is not None:
            try:
                os.close(self._pty_master)
            except OSError:
                pass
            self._pty_master = None
        super().close()
