"""Centralized Theme System for SuperLite OS"""

import json
import os
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Theme:
    """Theme configuration loaded from config file."""
    name: str = "midnight"
    bg: str = "#0f0f23"
    fg: str = "#e0e0f0"
    accent: str = "#e94560"
    accent_hover: str = "#ff6b81"
    surface: str = "#1a1a2e"
    surface_alt: str = "#16213e"
    border: str = "#0f3460"
    success: str = "#4ecca3"
    warning: str = "#f0c040"
    error: str = "#e94560"
    info: str = "#22d3ee"
    text_dim: str = "#808090"
    text_mid: str = "#a0a0b0"
    text_bright: str = "#e0e0f0"
    caret: str = "#e94560"
    selection: str = "#0f3460"

    @classmethod
    def from_config(cls, config: dict = None) -> "Theme":
        """Create a Theme from a config dict (typically config['theme'])."""
        if not config:
            return cls()
        return cls(
            name=config.get("name", "midnight"),
            bg=config.get("bg", "#0f0f23"),
            fg=config.get("fg", "#e0e0f0"),
            accent=config.get("accent", "#e94560"),
            accent_hover=config.get("accent_hover", "#ff6b81"),
            surface=config.get("surface", "#1a1a2e"),
            surface_alt=config.get("surface_alt", "#16213e"),
            border=config.get("border", "#0f3460"),
            success=config.get("success", "#4ecca3"),
            warning=config.get("warning", "#f0c040"),
            error=config.get("error", "#e94560"),
            info=config.get("info", "#22d3ee"),
            text_dim=config.get("text_dim", "#808090"),
            text_mid=config.get("text_mid", "#a0a0b0"),
            text_bright=config.get("text_bright", "#e0e0f0"),
            caret=config.get("caret", "#e94560"),
            selection=config.get("selection", "#0f3460"),
        )

    def to_css_vars(self) -> str:
        """Generate CSS custom properties block."""
        return f"""
        @define-color sl-bg {self.bg};
        @define-color sl-fg {self.fg};
        @define-color sl-accent {self.accent};
        @define-color sl-accent-hover {self.accent_hover};
        @define-color sl-surface {self.surface};
        @define-color sl-surface-alt {self.surface_alt};
        @define-color sl-border {self.border};
        @define-color sl-success {self.success};
        @define-color sl-warning {self.warning};
        @define-color sl-error {self.error};
        @define-color sl-info {self.info};
        @define-color sl-text-dim {self.text_dim};
        @define-color sl-text-mid {self.text_mid};
        @define-color sl-text-bright {self.text_bright};
        @define-color sl-caret {self.caret};
        @define-color sl-selection {self.selection};
        """

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "bg": self.bg,
            "fg": self.fg,
            "accent": self.accent,
            "accent_hover": self.accent_hover,
            "surface": self.surface,
            "surface_alt": self.surface_alt,
            "border": self.border,
            "success": self.success,
            "warning": self.warning,
            "error": self.error,
            "info": self.info,
            "text_dim": self.text_dim,
            "text_mid": self.text_mid,
            "text_bright": self.text_bright,
            "caret": self.caret,
            "selection": self.selection,
        }


# Global singleton — set during session init
_current_theme: Optional[Theme] = None


def get_theme() -> Theme:
    """Get the current theme (creates default if not initialized)."""
    global _current_theme
    if _current_theme is None:
        _current_theme = Theme()
    return _current_theme


def set_theme(theme: Theme):
    """Set the current theme."""
    global _current_theme
    _current_theme = theme


def load_theme_from_config(config_path: str = None) -> Theme:
    """Load theme from a config JSON file."""
    path = config_path or os.path.expanduser("~/.config/superlite/config.json")
    if os.path.isfile(path):
        try:
            with open(path) as f:
                data = json.load(f)
            theme = Theme.from_config(data.get("theme", {}))
            set_theme(theme)
            return theme
        except (json.JSONDecodeError, OSError):
            pass
    theme = Theme()
    set_theme(theme)
    return theme
