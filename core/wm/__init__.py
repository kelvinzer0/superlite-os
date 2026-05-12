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

        # Track window close
        window.connect("close-request", lambda w: self.unregister_window(w))

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
            if w.window is window:
                return w
        return None

    def _focus(self, entry: WindowEntry):
        """Focus a window."""
        if self.focused:
            self.focused.focused = False
        entry.focused = True
        self.focused = entry
        entry.window.present()

    def _relayout(self):
        """Recompute window positions based on current layout."""
        ws = self.workspaces[self.current_workspace]
        visible = [w for w in ws.windows if not w.minimized]
        if not visible:
            return

        if ws.layout == LayoutMode.TILING:
            self._tile(visible)

    def _tile(self, windows: list[WindowEntry]):
        """Tile windows in master-stack layout."""
        if not windows:
            return
        screen_w, screen_h = 1280, 720
        panel_height = 36
        usable_h = screen_h - panel_height
        gap = self.GAP

        if len(windows) == 1:
            w = windows[0]
            w.x, w.y = gap, panel_height + gap
            w.width = screen_w - 2 * gap
            w.height = usable_h - 2 * gap
            return

        master = windows[0]
        master_w = screen_w // 2 - gap
        master.x, master.y = gap, panel_height + gap
        master.width = master_w - gap
        master.height = usable_h - 2 * gap

        stack = windows[1:]
        stack_x = screen_w // 2 + gap
        stack_w = screen_w // 2 - 2 * gap
        stack_h = (usable_h - gap * (len(stack) + 1)) // len(stack)

        for i, w in enumerate(stack):
            w.x = stack_x
            w.y = panel_height + gap + i * (stack_h + gap)
            w.width = stack_w
            w.height = stack_h

    def get_workspace_info(self) -> list[dict]:
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
