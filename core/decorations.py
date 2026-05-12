"""Window Decorations - Custom titlebar with min/max/close buttons"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk, GLib

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
    .sl-titlebar {
        background: #1a1a2e;
        border-bottom: 1px solid #16213e;
        padding: 0 4px;
        min-height: 32px;
    }
    .sl-titlebar-icon {
        font-size: 14px;
        margin-right: 8px;
    }
    .sl-titlebar-label {
        color: #e0e0f0;
        font-size: 12px;
        font-weight: bold;
    }
    .sl-titlebar-btn {
        background: transparent;
        border: none;
        border-radius: 4px;
        min-width: 28px;
        min-height: 28px;
        padding: 0;
        font-size: 13px;
    }
    .sl-titlebar-btn:hover {
        background: #16213e;
    }
    .sl-btn-close:hover {
        background: #e94560;
        color: white;
    }
    .sl-btn-minimize:hover {
        background: #f0c040;
        color: #1a1a2e;
    }
    .sl-btn-maximize:hover {
        background: #4ecca3;
        color: #1a1a2e;
    }
    .sl-btn-min {
        background: #f0c040;
        border-radius: 50%;
        min-width: 12px;
        min-height: 12px;
        margin: 2px;
    }
    .sl-btn-max {
        background: #4ecca3;
        border-radius: 50%;
        min-width: 12px;
        min-height: 12px;
        margin: 2px;
    }
    .sl-btn-cls {
        background: #e94560;
        border-radius: 50%;
        min-width: 12px;
        min-height: 12px;
        margin: 2px;
    }
    .sl-separator {
        background: #16213e;
        min-width: 1px;
        min-height: 20px;
        margin: 0 4px;
    }
    """
    p = Gtk.CssProvider()
    p.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(d, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def apply_titlebar(window: Gtk.Window, icon: str = "⚡", title: str = None):
    """
    Apply a custom SuperLite titlebar to any GTK4 window.
    
    Args:
        window: The GTK4 window to decorate
        icon: Icon emoji for the titlebar
        title: Title text (defaults to window's current title)
    """
    _ensure_css()
    
    if title is None:
        title = window.get_title() or "SuperLite"
    
    # Prevent GTK from using default decorations
    window.set_decorated(False)
    
    # Titlebar container
    titlebar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
    titlebar.add_css_class("sl-titlebar")
    titlebar.set_size_request(-1, 32)
    
    # Traffic light buttons (macOS style)
    btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
    btn_box.set_margin_start(8)
    btn_box.set_margin_top(6)
    btn_box.set_margin_bottom(6)
    
    close_btn = Gtk.Button()
    close_btn.add_css_class("sl-btn-cls")
    close_btn.set_tooltip_text("Close")
    close_btn.connect("clicked", lambda _: window.close())
    btn_box.append(close_btn)
    
    min_btn = Gtk.Button()
    min_btn.add_css_class("sl-btn-min")
    min_btn.set_tooltip_text("Minimize")
    min_btn.connect("clicked", lambda _: window.minimize())
    btn_box.append(min_btn)
    
    max_btn = Gtk.Button()
    max_btn.add_css_class("sl-btn-max")
    max_btn.set_tooltip_text("Maximize")
    max_btn.connect("clicked", lambda _: _toggle_maximize(window, max_btn))
    btn_box.append(max_btn)
    
    titlebar.append(btn_box)
    
    # Separator
    sep = Gtk.Box()
    sep.add_css_class("sl-separator")
    titlebar.append(sep)
    
    # Icon
    icon_label = Gtk.Label(label=icon)
    icon_label.add_css_class("sl-titlebar-icon")
    titlebar.append(icon_label)
    
    # Title
    title_label = Gtk.Label(label=title)
    title_label.add_css_class("sl-titlebar-label")
    title_label.set_hexpand(True)
    title_label.set_xalign(0)
    title_label.set_ellipsize(3)  # Pango.EllipsizeMode.END
    titlebar.append(title_label)
    
    # Make titlebar draggable
    drag = Gtk.GestureDrag()
    drag.connect("drag-begin", lambda g, x, y: _start_drag(window, g, x, y))
    titlebar.add_controller(drag)
    
    # Double-click to maximize
    click = Gtk.GestureClick()
    click.connect("released", lambda g, n, x, y: _toggle_maximize(window, max_btn) if n >= 2 else None)
    titlebar.add_controller(click)
    
    window.set_titlebar(titlebar)
    return titlebar


def _toggle_maximize(window: Gtk.Window, btn: Gtk.Button):
    if window.is_maximized():
        window.unmaximize()
    else:
        window.maximize()


def _start_drag(window, gesture, x, y):
    """Initiate window drag from titlebar."""
    # In GTK4, window dragging from titlebar is handled by set_titlebar()
    # This is a fallback for custom drag handling
    pass
