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

    def _get_screen_size(self) -> tuple[int, int]:
        """Query actual display geometry. Falls back to 1280x720."""
        try:
            if self.display:
                monitors = self.display.get_monitors()
                if monitors and monitors.get_n_items() > 0:
                    monitor = monitors.get_item(0)
                    geo = monitor.get_geometry()
                    return geo.width, geo.height
        except Exception:
            pass
        return 1280, 720

    def register_window(self, window: Gtk.Window, app_id: str, title: str = "") -> WindowEntry:
        """Register a new window with the WM and apply tiling layout."""
        entry = WindowEntry(
            window=window,
            app_id=app_id,
            title=title or app_id,
            workspace=self.current_workspace,
        )
        self.windows.append(entry)
        self.workspaces[self.current_workspace].windows.append(entry)

        # Track window close — return False to allow the window to actually close
        window.connect("close-request", lambda w: self.unregister_window(w))

        # Relayout first (compute positions), then apply geometry, then focus
        self._relayout()
        self._apply_geometry(entry)
        self._focus(entry)

        return entry

    def unregister_window(self, window: Gtk.Window) -> bool:
        """Remove a window from WM tracking. Returns False to allow close."""
        entry = self._find_entry(window)
        if not entry:
            return False
        self.windows.remove(entry)
        ws = self.workspaces[entry.workspace]
        if entry in ws.windows:
            ws.windows.remove(entry)
        if self.focused == entry:
            self.focused = None
            if ws.windows:
                self._focus(ws.windows[-1])
        self._relayout()
        return False  # Allow the window to close

    def _find_entry(self, window: Gtk.Window) -> Optional[WindowEntry]:
        for w in self.windows:
            if w.window is window:
                return w
        return None

    def _focus(self, entry: WindowEntry):
        """Focus a window and raise it to top of stack."""
        if self.focused and self.focused is not entry:
            self.focused.focused = False
        entry.focused = True
        self.focused = entry
        # Raise focused window to top — use idle_add to ensure it happens
        # after any pending GTK events (like launcher closing)
        GLib.idle_add(self._do_raise, entry)

    def _do_raise(self, entry: WindowEntry) -> bool:
        """Actually raise the window (called via idle_add)."""
        if entry in self.windows and entry.window.get_visible():
            entry.window.present()
            # Also restack: ensure focused window is above all others
            self._enforce_stacking()
        return False  # Don't repeat

    def _enforce_stacking(self):
        """Ensure proper z-ordering: focused on top, tiled windows don't overlap."""
        if not self.focused:
            return
        ws = self.workspaces[self.current_workspace]
        visible = [w for w in ws.windows if not w.minimized and w is not self.focused]
        # Raise focused last so it's on top
        for entry in visible:
            try:
                entry.window.present()
            except Exception:
                pass
        # Focused window is last → on top
        try:
            self.focused.window.present()
        except Exception:
            pass

    def _apply_geometry(self, entry: WindowEntry):
        """Apply computed position and size to a GTK window."""
        entry.window.set_default_size(entry.width, entry.height)
        try:
            surface = entry.window.get_surface()
            if surface is not None:
                surface.set_position(entry.x, entry.y)
        except (AttributeError, TypeError):
            pass

    def _switch_workspace(self, workspace_id: int):
        """Switch to a different workspace, hiding/showing windows."""
        if workspace_id < 0 or workspace_id >= self.WORKSPACE_COUNT:
            return
        if workspace_id == self.current_workspace:
            return

        old_ws = self.workspaces[self.current_workspace]
        new_ws = self.workspaces[workspace_id]

        # Hide windows from old workspace
        for entry in old_ws.windows:
            if not entry.minimized:
                entry.window.set_visible(False)

        self.current_workspace = workspace_id

        # Show windows in new workspace
        for entry in new_ws.windows:
            if not entry.minimized:
                entry.window.set_visible(True)

        # Focus the last window in new workspace (if any)
        if new_ws.windows:
            self._focus(new_ws.windows[-1])
        else:
            self.focused = None

        self._relayout()

    def focus_next(self):
        """Cycle focus to next window in current workspace."""
        ws = self.workspaces[self.current_workspace]
        visible = [w for w in ws.windows if not w.minimized]
        if len(visible) <= 1:
            return
        if self.focused in visible:
            idx = visible.index(self.focused)
            self._focus(visible[(idx + 1) % len(visible)])
        elif visible:
            self._focus(visible[0])

    def focus_prev(self):
        """Cycle focus to previous window in current workspace."""
        ws = self.workspaces[self.current_workspace]
        visible = [w for w in ws.windows if not w.minimized]
        if len(visible) <= 1:
            return
        if self.focused in visible:
            idx = visible.index(self.focused)
            self._focus(visible[(idx - 1) % len(visible)])
        elif visible:
            self._focus(visible[-1])

    def close_focused(self):
        """Close the currently focused window."""
        if self.focused:
            self.focused.window.close()

    def toggle_maximize_focused(self):
        """Toggle maximize on focused window."""
        if not self.focused:
            return
        win = self.focused.window
        if win.is_maximized():
            win.unmaximize()
        else:
            win.maximize()

    def minimize_focused(self):
        """Minimize the focused window."""
        if self.focused:
            self.focused.minimized = True
            self.focused.window.set_visible(False)
            self.focused = None
            ws = self.workspaces[self.current_workspace]
            visible = [w for w in ws.windows if not w.minimized]
            if visible:
                self._focus(visible[-1])
            self._relayout()

    def toggle_floating_focused(self):
        """Toggle floating/tiling for focused window."""
        if not self.focused:
            return
        ws = self.workspaces[self.current_workspace]
        if ws.layout == LayoutMode.TILING:
            ws.layout = LayoutMode.FLOATING
        else:
            ws.layout = LayoutMode.TILING
        self._relayout()

    def _relayout(self):
        """Recompute window positions based on current layout."""
        ws = self.workspaces[self.current_workspace]
        visible = [w for w in ws.windows if not w.minimized]
        if not visible:
            return

        if ws.layout == LayoutMode.TILING:
            self._tile(visible)
            # Apply geometry to all visible windows
            for entry in visible:
                self._apply_geometry(entry)

    def _tile(self, windows: list[WindowEntry]):
        """Tile windows in master-stack layout."""
        if not windows:
            return
        screen_w, screen_h = self._get_screen_size()
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
