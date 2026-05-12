"""Browser Launcher - Chrome/Chromium launcher with sandbox flags"""

import os
import subprocess
import shutil
from dataclasses import dataclass
from typing import Optional


@dataclass
class BrowserProfile:
    name: str
    data_dir: str
    extra_args: list[str]


class BrowserLauncher:
    """
    Chrome/Chromium launcher optimized for SuperLite OS.
    Handles sandbox configuration, profile management, and resource limits.
    """

    CHROME_SEARCH_PATHS = [
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/opt/google/chrome/chrome",
        "/snap/bin/chromium",
    ]

    DEFAULT_FLAGS = [
        "--no-first-run",
        "--disable-sync",
        "--disable-translate",
        "--disable-extensions",  # Keep lean
        "--disable-background-networking",
        "--disable-client-side-phishing-detection",
        "--disable-default-apps",
        "--disable-hang-monitor",
        "--disable-popup-blocking",
        "--disable-prompt-on-repost",
        "--metrics-recording-only",
        "--safebrowsing-disable-auto-update",
        # Memory optimization for flashdisk OS
        "--disk-cache-size=52428800",  # 50MB cache
        "--media-cache-size=52428800",
        "--max-old-space-size=256",
        # Disable GPU if no proper drivers
        "--disable-gpu-sandbox",
    ]

    def __init__(self, profile_dir: str = None):
        self.chrome_path = self._find_chrome()
        self.profile_dir = profile_dir or os.path.expanduser("~/.config/superlite/chrome")
        self.profiles: dict[str, BrowserProfile] = {}
        self._load_profiles()

    def _find_chrome(self) -> Optional[str]:
        """Find Chrome/Chromium binary."""
        for path in self.CHROME_SEARCH_PATHS:
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        # Try which
        result = shutil.which("google-chrome") or shutil.which("chromium")
        return result

    def _load_profiles(self):
        """Load saved browser profiles."""
        default_profile = BrowserProfile(
            name="default",
            data_dir=os.path.join(self.profile_dir, "default"),
            extra_args=[],
        )
        self.profiles["default"] = default_profile

    def launch(
        self,
        url: str = None,
        profile: str = "default",
        incognito: bool = False,
        new_window: bool = False,
        extra_args: list[str] = None,
    ) -> Optional[subprocess.Popen]:
        """Launch Chrome with configured options."""
        if not self.chrome_path:
            print("[Browser] Chrome/Chromium not found!")
            return None

        prof = self.profiles.get(profile, self.profiles["default"])

        # Ensure profile directory exists
        os.makedirs(prof.data_dir, exist_ok=True)

        args = [
            self.chrome_path,
            f"--user-data-dir={prof.data_dir}",
            *self.DEFAULT_FLAGS,
            *prof.extra_args,
        ]

        if incognito:
            args.append("--incognito")

        if new_window:
            args.append("--new-window")

        if extra_args:
            args.extend(extra_args)

        if url:
            args.append(url)
        elif new_window or not url:
            args.append("chrome://newtab")

        print(f"[Browser] Launching: {' '.join(args[:5])}...")

        try:
            proc = subprocess.Popen(
                args,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                preexec_fn=os.setsid,
            )
            return proc
        except Exception as e:
            print(f"[Browser] Launch failed: {e}")
            return None

    def create_profile(self, name: str, extra_args: list[str] = None) -> BrowserProfile:
        """Create a new browser profile."""
        profile = BrowserProfile(
            name=name,
            data_dir=os.path.join(self.profile_dir, name),
            extra_args=extra_args or [],
        )
        self.profiles[name] = profile
        os.makedirs(profile.data_dir, exist_ok=True)
        return profile

    def list_profiles(self) -> list[str]:
        return list(self.profiles.keys())

    def is_available(self) -> bool:
        return self.chrome_path is not None

    def get_version(self) -> Optional[str]:
        if not self.chrome_path:
            return None
        try:
            result = subprocess.run(
                [self.chrome_path, "--version"],
                capture_output=True, text=True, timeout=5,
            )
            return result.stdout.strip()
        except Exception:
            return None
