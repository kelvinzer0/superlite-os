"""Terminal Emulator - VTE-based terminal"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib, Pango
import os
import subprocess
import threading
import pty
import select
import signal


class TerminalWindow(Gtk.Window):
    """Lightweight terminal emulator using PTY."""

    DEFAULT_FONT = "Monospace 11"
    COLORS = {
        "bg": "#0f0f23",
        "fg": "#e0e0f0",
        "cursor": "#e94560",
        "selection": "#16213e",
        "black": "#1a1a2e",
        "red": "#e94560",
        "green": "#4ecca3",
        "yellow": "#f0c040",
        "blue": "#0f3460",
        "magenta": "#a855f7",
        "cyan": "#22d3ee",
        "white": "#e0e0f0",
    }

    def __init__(self, cwd: str = None):
        super().__init__()
        self.set_title("Terminal")
        self.set_default_size(800, 500)
        self.add_css_class("terminal-window")

        self.cwd = cwd or os.path.expanduser("~")
        self._pty_master = None
        self._pty_slave = None
        self._child_pid = None

        # Main container
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(box)

        # Toolbar
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        toolbar.add_css_class("terminal-toolbar")

        new_tab_btn = Gtk.Button(label="+")
        new_tab_btn.set_tooltip_text("New tab")
        new_tab_btn.add_css_class("terminal-tab-btn")

        cwd_label = Gtk.Label(label=f"📁 {self.cwd}")
        cwd_label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        cwd_label.set_hexpand(True)
        cwd_label.set_xalign(0)

        toolbar.append(new_tab_btn)
        toolbar.append(cwd_label)
        box.append(toolbar)

        # Terminal output (ScrollableTextView)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_hexpand(True)

        self.text_view = Gtk.TextView()
        self.text_view.set_editable(False)
        self.text_view.set_cursor_visible(False)
        self.text_view.set_monospace(True)
        self.text_view.set_wrap_mode(Gtk.WrapMode.CHAR)
        self.text_view.add_css_class("terminal-output")

        # Buffer with color tags
        self.buffer = self.text_view.get_buffer()
        self._setup_tags()

        scroll.set_child(self.text_view)
        box.append(scroll)

        # Input bar
        input_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        input_box.add_css_class("terminal-input-bar")

        self.prompt_label = Gtk.Label(label="$")
        self.prompt_label.add_css_class("terminal-prompt")

        self.input_entry = Gtk.Entry()
        self.input_entry.set_hexpand(True)
        self.input_entry.set_placeholder_text("Type command...")
        self.input_entry.add_css_class("terminal-input")
        self.input_entry.connect("activate", self._on_command)
        self.input_entry.grab_focus()

        input_box.append(self.prompt_label)
        input_box.append(self.input_entry)
        box.append(input_box)

        # Apply CSS
        self._apply_style()

        # Start shell
        self._start_shell()

        # Key bindings
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect("key-pressed", self._on_key)
        self.add_controller(key_ctrl)

    def _setup_tags(self):
        """Create text buffer tags for colored output."""
        for name, color in self.COLORS.items():
            tag = self.buffer.create_tag(name)
            if name == "bg":
                tag.set_property("background", color)
            elif name == "fg":
                tag.set_property("foreground", color)
            elif name in ("red", "green", "yellow", "blue", "magenta", "cyan", "white", "black"):
                tag.set_property("foreground", color)

    def _start_shell(self):
        """Start a PTY-based shell."""
        shell = os.environ.get("SHELL", "/bin/bash")
        master, slave = pty.openpty()
        self._pty_master = master
        self._pty_slave = slave

        self._child_pid = os.fork()
        if self._child_pid == 0:
            # Child process
            os.close(master)
            os.setsid()
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.chdir(self.cwd)
            os.execvp(shell, [shell, "--login"])
        else:
            # Parent
            os.close(slave)
            self._read_pty()

    def _read_pty(self):
        """Read output from PTY in background."""
        def reader():
            while True:
                try:
                    r, _, _ = select.select([self._pty_master], [], [], 0.1)
                    if r:
                        data = os.read(self._pty_master, 4096)
                        if data:
                            text = data.decode("utf-8", errors="replace")
                            GLib.idle_add(self._append_output, text)
                except (OSError, ValueError):
                    break

        thread = threading.Thread(target=reader, daemon=True)
        thread.start()

    def _append_output(self, text: str):
        """Append text to terminal output."""
        end_iter = self.buffer.get_end_iter()
        self.buffer.insert_with_tags_by_name(end_iter, text, "fg")
        # Auto-scroll
        mark = self.buffer.get_insert()
        self.text_view.scroll_mark_onscreen(mark)

    def _on_command(self, entry):
        """Handle command input."""
        cmd = entry.get_text()
        entry.set_text("")
        if cmd.strip():
            os.write(self._pty_master, (cmd + "\n").encode())

    def _on_key(self, controller, keyval, keycode, state):
        """Handle special key combinations."""
        ctrl = state & Gdk.ModifierType.CONTROL_MASK
        if ctrl and keyval == Gdk.KEY_c:
            if self._child_pid:
                os.kill(self._child_pid, signal.SIGINT)
            return True
        elif ctrl and keyval == Gdk.KEY_l:
            self.buffer.set_text("")
            return True
        elif ctrl and keyval == Gdk.KEY_d:
            self.close()
            return True
        return False

    def _apply_style(self):
        css = f"""
        .terminal-window {{
            background: {self.COLORS['bg']};
        }}
        .terminal-toolbar {{
            background: #1a1a2e;
            padding: 4px 8px;
            border-bottom: 1px solid #16213e;
        }}
        .terminal-tab-btn {{
            background: #16213e;
            color: #e94560;
            border: 1px solid #0f3460;
            border-radius: 3px;
            min-width: 24px;
            font-weight: bold;
        }}
        .terminal-output {{
            background: {self.COLORS['bg']};
            color: {self.COLORS['fg']};
            font-family: monospace;
            font-size: 13px;
            padding: 8px;
        }}
        .terminal-input-bar {{
            background: #1a1a2e;
            padding: 4px 8px;
            border-top: 1px solid #16213e;
        }}
        .terminal-prompt {{
            color: {self.COLORS['green']};
            font-weight: bold;
            font-family: monospace;
        }}
        .terminal-input {{
            background: #0f0f23;
            color: {self.COLORS['fg']};
            border: 1px solid #16213e;
            border-radius: 4px;
            padding: 4px 8px;
            font-family: monospace;
            caret-color: {self.COLORS['cursor']};
        }}
        """.encode()
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    def close(self):
        """Clean up PTY on close."""
        if self._child_pid:
            try:
                os.kill(self._child_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if self._pty_master:
            os.close(self._pty_master)
        super().close()
