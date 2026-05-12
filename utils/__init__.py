"""SuperLite OS - Shared Utilities"""

import os
import json
import logging
from pathlib import Path
from typing import Any


# ─── Logging ───────────────────────────────────────────────

def setup_logger(name: str, level: int = logging.INFO) -> logging.Logger:
    """Setup a formatted logger."""
    logger = logging.getLogger(name)
    logger.setLevel(level)

    if not logger.handlers:
        handler = logging.StreamHandler()
        formatter = logging.Formatter(
            "[%(asctime)s] %(name)s %(levelname)s: %(message)s",
            datefmt="%H:%M:%S",
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    return logger


# ─── Config ────────────────────────────────────────────────

class Config:
    """JSON-based configuration with defaults."""

    DEFAULTS = {
        "wm": {
            "gap": 4,
            "border_width": 2,
            "workspaces": 4,
            "layout": "tiling",
        },
        "panel": {
            "position": "top",
            "height": 36,
            "show_battery": True,
        },
        "theme": {
            "name": "midnight",
            "bg": "#0f0f23",
            "fg": "#e0e0f0",
            "accent": "#e94560",
            "surface": "#1a1a2e",
            "border": "#16213e",
        },
        "terminal": {
            "font": "Monospace 11",
            "scrollback": 10000,
            "cursor_style": "block",
        },
        "filemanager": {
            "show_hidden": False,
            "sort_dirs_first": True,
            "view_mode": "list",
        },
        "editor": {
            "font": "Monospace 13",
            "tab_width": 4,
            "show_line_numbers": True,
            "word_wrap": False,
        },
    }

    def __init__(self, path: str = None):
        self.path = path or os.path.expanduser("~/.config/superlite/config.json")
        self._data: dict = {}
        self.load()

    def load(self):
        """Load config from file, merge with defaults."""
        if os.path.isfile(self.path):
            try:
                with open(self.path) as f:
                    self._data = json.load(f)
            except (json.JSONDecodeError, OSError):
                self._data = {}
        self._merge_defaults()

    def save(self):
        """Save config to file."""
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "w") as f:
            json.dump(self._data, f, indent=2)

    def get(self, key: str, default: Any = None) -> Any:
        """Get config value by dot-separated key path."""
        keys = key.split(".")
        value = self._data
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        return value

    def set(self, key: str, value: Any):
        """Set config value by dot-separated key path."""
        keys = key.split(".")
        data = self._data
        for k in keys[:-1]:
            if k not in data or not isinstance(data[k], dict):
                data[k] = {}
            data = data[k]
        data[keys[-1]] = value

    def _merge_defaults(self):
        """Merge defaults into loaded config."""
        def merge(base: dict, overlay: dict):
            for k, v in overlay.items():
                if k not in base:
                    base[k] = v
                elif isinstance(base[k], dict) and isinstance(v, dict):
                    merge(base[k], v)
        merge(self._data, self.DEFAULTS)


# ─── Paths ─────────────────────────────────────────────────

class Paths:
    """Standard paths for SuperLite OS."""

    @staticmethod
    def home() -> str:
        return os.path.expanduser("~")

    @staticmethod
    def config() -> str:
        return os.path.expanduser("~/.config/superlite")

    @staticmethod
    def cache() -> str:
        return os.path.expanduser("~/.cache/superlite")

    @staticmethod
    def data() -> str:
        return os.path.expanduser("~/.local/share/superlite")

    @staticmethod
    def driver_dump() -> str:
        return os.path.expanduser("~/.superlite/driver-dump")

    @staticmethod
    def build() -> str:
        return os.path.expanduser("~/.superlite/build")


# ─── Process ───────────────────────────────────────────────

def run_cmd(cmd: list[str], timeout: int = 30, check: bool = False) -> tuple[int, str, str]:
    """Run a command and return (returncode, stdout, stderr)."""
    import subprocess
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if check and result.returncode != 0:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{result.stderr}")
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except FileNotFoundError:
        return -127, "", f"Command not found: {cmd[0]}"


def is_root() -> bool:
    return os.geteuid() == 0


def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)
