"""Window Decorations - Simplified for running inside host WM (openbox)"""

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gdk

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
        @define-color sl-fg #e0e0f0;
        @define-color sl-accent #e94560;
        @define-color sl-surface #1a1a2e;
        @define-color sl-surface-alt #16213e;
        @define-color sl-border #0f3460;
        @define-color sl-success #4ecca3;
        @define-color sl-warning #f0c040;
        @define-color sl-text-dim #808090;
        @define-color sl-text-bright #e0e0f0;
        @define-color sl-caret #e94560;
        """
    css = vars_css.encode() + b"""
    .sl-window {
        background: @sl-bg;
        color: @sl-text-bright;
    }
    .sl-titlebar {
        background: @sl-surface;
        border-bottom: 1px solid @sl-surface-alt;
        padding: 0 8px;
        min-height: 28px;
    }
    .sl-titlebar-label {
        color: @sl-text-bright;
        font-size: 11px;
        font-weight: bold;
    }
    .sl-btn {
        background: transparent;
        border: none;
        border-radius: 4px;
        min-width: 24px;
        min-height: 24px;
        padding: 0;
        font-size: 14px;
        color: @sl-text-dim;
    }
    .sl-btn:hover {
        background: @sl-surface-alt;
        color: @sl-text-bright;
    }
    .sl-btn-close:hover {
        background: @sl-accent;
        color: white;
    }
    .sl-btn-icon {
        background: @sl-accent;
        border-radius: 50%;
        min-width: 10px;
        min-height: 10px;
    }
    """
    p = Gtk.CssProvider()
    p.load_from_data(css)
    Gtk.StyleContext.add_provider_for_display(d, p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)


def apply_titlebar(window: Gtk.Window, icon: str = "⚡", title: str = None):
    """Apply a minimal custom titlebar. Keep native decorations for min/max/close to work."""
    _ensure_css()

    if title is None:
        title = window.get_title() or "SuperLite"

    # Keep native decorations — openbox handles min/max/close properly
    # Just add a styled header bar inside the content area
    header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    header.add_css_class("sl-titlebar")
    header.set_size_request(-1, 28)

    icon_label = Gtk.Label(label=icon)
    header.append(icon_label)

    title_label = Gtk.Label(label=title)
    title_label.add_css_class("sl-titlebar-label")
    title_label.set_hexpand(True)
    title_label.set_xalign(0)
    title_label.set_ellipsize(3)
    header.append(title_label)

    return header
