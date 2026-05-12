"""Window Manager - Tiling & Floating hybrid"""

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gtk, Gdk, GLib
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional


class LayoutMode(Enum):
    TILING = auto()
    FLOATING = auto()
    MAXIMIZED = auto()


@dataclass
class WindowEntry:
    window: Gtk.Window
    app_id: str
    title: str
    x: int = 0
    y: int = 0
    width: int = 800
    height: int = 600
    focused: bool = False
    minimized: bool = False
    maximized: bool = False
    workspace: int = 0


@dataclass
class Workspace:
    id: int
    name: str
    layout: LayoutMode = LayoutMode.TILING
    windows: list = field(default_factory=list)


class WindowManager:
    """Hybrid tiling/floating window manager for SuperLite OS."""

    GAP = 4
    BORDER_WIDTH = 2
    WORKSPACE_COUNT = 4

    def __init__(self, display: Optional[Gdk.Display] = None):
        self.display = display or Gdk.Display.get_default()
        self.workspaces = [
            Workspace(id=i, name=f"WS {i+1}")
            for i in range(self.WORKSPACE_COUNT)
        ]
        self.current_workspace = 0
        self.windows: list[WindowEntry] = []
        self.focused: Optional[WindowEntry] = None
        self._key_bindings: dict[str, callable] = {}
        self._setup_keybindings()

    def _setup_keybindings(self):
        """Register global keybindings for WM operations."""
        self._keybindings_map = {
            "<Super>Return": self._toggle_layout,
            "<Super>q": self._close_focused,
            "<Super>j": self._focus_next,
            "<Super>k": self._focus_prev,
            "<Super>f": self._toggle_maximize,
            "<Super>m": self._minimize_focused,
            "<Super>space": self._toggle_floating,
        }
        # Workspace switching: Super+1-4
        for i in range(self.WORKSPACE_COUNT):
            self._keybindings_map[f"<Super>{i+1}"] = lambda ws=i: self._switch_workspace(ws)

    def register_window(self, window: Gtk.Window, app_id: str, title: str = "") -> WindowEntry:
        """Register a new window with the WM."""
        entry = WindowEntry(
            window=window,
            app_id=app_id,
            title=title or app_id,
            workspace=self.current_workspace,
        )
        self.windows.append(entry)
        self.workspaces[self.current_workspace].windows.append(entry)
        self._focus(entry)
        self._relayout()
        return entry

    def unregister_window(self, window: Gtk.Window):
        """Remove a window from WM tracking."""
        entry = self._find_entry(window)
        if not entry:
            return
        self.windows.remove(entry)
        ws = self.workspaces[entry.workspace]
        if entry in ws.windows:
            ws.windows.remove(entry)
        if self.focused == entry:
            self.focused = None
            if ws.windows:
                self._focus(ws.windows[-1])
        self._relayout()

    def _find_entry(self, window: Gtk.Window) -> Optional[WindowEntry]:
        for w in self.windows:
            if w.window == window:
                return w
        return None

    def _focus(self, entry: WindowEntry):
        """Focus a window."""
        if self.focused:
            self.focused.focused = False
        entry.focused = True
        self.focused = entry
        entry.window.present()

    def _focus_next(self):
        ws = self.workspaces[self.current_workspace]
        if not ws.windows:
            return
        if not self.focused or self.focused not in ws.windows:
            self._focus(ws.windows[0])
            return
        idx = ws.windows.index(self.focused)
        self._focus(ws.windows[(idx + 1) % len(ws.windows)])

    def _focus_prev(self):
        ws = self.workspaces[self.current_workspace]
        if not ws.windows:
            return
        if not self.focused or self.focused not in ws.windows:
            self._focus(ws.windows[-1])
            return
        idx = ws.windows.index(self.focused)
        self._focus(ws.windows[(idx - 1) % len(ws.windows)])

    def _close_focused(self):
        if self.focused:
            self.focused.window.close()

    def _toggle_maximize(self):
        if not self.focused:
            return
        self.focused.maximized = not self.focused.maximized
        self._relayout()

    def _minimize_focused(self):
        if not self.focused:
            return
        self.focused.minimized = not self.focused.minimized
        self._relayout()

    def _toggle_floating(self):
        ws = self.workspaces[self.current_workspace]
        if ws.layout == LayoutMode.FLOATING:
            ws.layout = LayoutMode.TILING
        else:
            ws.layout = LayoutMode.FLOATING
        self._relayout()

    def _toggle_layout(self):
        ws = self.workspaces[self.current_workspace]
        modes = list(LayoutMode)
        idx = modes.index(ws.layout)
        ws.layout = modes[(idx + 1) % len(modes)]
        self._relayout()

    def _switch_workspace(self, workspace_id: int):
        if workspace_id == self.current_workspace:
            return
        # Hide current windows
        ws_old = self.workspaces[self.current_workspace]
        for entry in ws_old.windows:
            entry.window.set_visible(False)
        # Show new workspace windows
        self.current_workspace = workspace_id
        ws_new = self.workspaces[workspace_id]
        for entry in ws_new.windows:
            entry.window.set_visible(True)
        if ws_new.windows:
            self._focus(ws_new.windows[0])

    def _relayout(self):
        """Recompute window positions based on current layout."""
        ws = self.workspaces[self.current_workspace]
        visible = [w for w in ws.windows if not w.minimized]
        if not visible:
            return

        if ws.layout == LayoutMode.TILING:
            self._tile(visible)
        elif ws.layout == LayoutMode.FLOATING:
            pass  # Floating = user positions
        elif ws.layout == LayoutMode.MAXIMIZED:
            self._maximize_all(visible)

    def _tile(self, windows: list[WindowEntry]):
        """Tile windows in master-stack layout."""
        if not windows:
            return
        # Get screen dimensions (fallback for development)
        try:
            surface = windows[0].window.get_surface()
            if surface:
                screen_w = surface.get_width()
                screen_h = surface.get_height()
            else:
                screen_w, screen_h = 1920, 1080
        except Exception:
            screen_w, screen_h = 1920, 1080

        panel_height = 36
        usable_h = screen_h - panel_height
        gap = self.GAP

        if len(windows) == 1:
            w = windows[0]
            w.x, w.y = gap, panel_height + gap
            w.width = screen_w - 2 * gap
            w.height = usable_h - 2 * gap
            self._apply_geometry(w)
            return

        # Master window takes left half
        master = windows[0]
        master_w = screen_w // 2 - gap
        master.x, master.y = gap, panel_height + gap
        master.width = master_w - gap
        master.height = usable_h - 2 * gap
        self._apply_geometry(master)

        # Stack on right
        stack = windows[1:]
        stack_x = screen_w // 2 + gap
        stack_w = screen_w // 2 - 2 * gap
        stack_h = (usable_h - gap * (len(stack) + 1)) // len(stack)

        for i, w in enumerate(stack):
            w.x = stack_x
            w.y = panel_height + gap + i * (stack_h + gap)
            w.width = stack_w
            w.height = stack_h
            self._apply_geometry(w)

    def _maximize_all(self, windows: list[WindowEntry]):
        """Maximize all visible windows (fullscreen-like)."""
        for w in windows:
            w.x, w.y = 0, 36
            w.width, w.height = 1920, 1080 - 36
            self._apply_geometry(w)

    def _apply_geometry(self, entry: WindowEntry):
        """Apply computed geometry to a window."""
        entry.window.set_default_size(entry.width, entry.height)

    def get_workspace_info(self) -> list[dict]:
        """Return workspace state for panel display."""
        return [
            {
                "id": ws.id,
                "name": ws.name,
                "layout": ws.layout.name,
                "window_count": len(ws.windows),
                "active": ws.id == self.current_workspace,
            }
            for ws in self.workspaces
        ]

    def get_window_list(self) -> list[dict]:
        """Return window list for taskbar."""
        ws = self.workspaces[self.current_workspace]
        return [
            {
                "app_id": w.app_id,
                "title": w.title,
                "focused": w.focused,
                "minimized": w.minimized,
            }
            for w in ws.windows
        ]
