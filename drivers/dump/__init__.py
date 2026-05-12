"""Driver Dump - Extract and package hardware drivers from running system

This module only operates in cross-chain mode (host → target).
It dumps drivers from the running host system to be embedded
into the SuperLite OS bootable image.
"""

import os
import json
import shutil
import subprocess
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional


@dataclass
class DriverInfo:
    """Metadata for a single driver."""
    name: str
    module: str  # kernel module name
    path: str  # path to .ko file
    type: str  # gpu, network, storage, usb, input, audio, etc.
    vendor: str = ""
    device_id: str = ""
    dependencies: list[str] = field(default_factory=list)
    firmware_files: list[str] = field(default_factory=list)
    size_bytes: int = 0
    loaded: bool = False


@dataclass
class DriverDumpManifest:
    """Complete manifest of dumped drivers."""
    source_kernel: str
    source_arch: str
    source_distro: str
    drivers: list[DriverInfo] = field(default_factory=list)
    firmware: list[str] = field(default_factory=list)
    total_size: int = 0
    dump_time: str = ""


class DriverDump:
    """
    Extracts hardware drivers from the running system.

    Cross-chain operation: runs on the HOST system to capture
    drivers needed by the TARGET hardware (flashdisk boot).

    Workflow:
    1. Detect running hardware (lspci, lsusb, lshw)
    2. Map hardware → kernel modules
    3. Extract .ko files + firmware blobs
    4. Generate dependency graph
    5. Package into portable bundle
    """

    DRIVER_TYPES = {
        "gpu": ["nvidia", "nouveau", "amdgpu", "radeon", "i915", "xe"],
        "network": ["iwlwifi", "ath9k", "rtw89", "r8169", "e1000e", "tg3", "bnxt_en", "mlx5"],
        "storage": ["ahci", "nvme", "sd_mod", "usb_storage", "mmc_block"],
        "usb": ["xhci_hcd", "ehci_hcd", "ohci_hcd", "usbhid", "hid_generic"],
        "input": ["evdev", "libps2", "atkbd", "mousedev"],
        "audio": ["snd_hda_intel", "snd_usb_audio", "snd_soc", "snd_sof"],
        "bluetooth": ["btusb", "bluetooth", "btintel", "btrtl"],
        "wifi": ["cfg80211", "mac80211", "iwlmvm"],
        "virtual": ["vboxguest", "vmw_balloon", "vmwgfx", "hyperv_drm", "virtio"],
    }

    def __init__(self, output_dir: str = None):
        self.output_dir = output_dir or os.path.expanduser("~/.superlite/driver-dump")
        self.manifest = DriverDumpManifest(
            source_kernel="",
            source_arch="",
            source_distro="",
        )

    def detect_hardware(self) -> dict:
        """Detect hardware using system tools."""
        hw = {
            "pci": [],
            "usb": [],
            "platform": [],
        }

        # PCI devices
        try:
            result = subprocess.run(
                ["lspci", "-nn", "-k"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                hw["pci"] = self._parse_lspci(result.stdout)
        except FileNotFoundError:
            # Fallback: read /sys directly
            hw["pci"] = self._detect_pci_sysfs()

        # USB devices
        try:
            result = subprocess.run(
                ["lsusb", "-v"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                hw["usb"] = self._parse_lsusb(result.stdout)
        except FileNotFoundError:
            hw["usb"] = self._detect_usb_sysfs()

        return hw

    def _parse_lspci(self, output: str) -> list[dict]:
        """Parse lspci -nn -k output."""
        devices = []
        current = None
        for line in output.strip().split("\n"):
            if not line.startswith("\t") and line.strip():
                if current:
                    devices.append(current)
                # Parse: "00:02.0 VGA compatible controller [0300]: Intel Corporation ..."
                parts = line.split(" ", 1)
                current = {
                    "slot": parts[0],
                    "description": parts[1] if len(parts) > 1 else "",
                    "modules": [],
                }
            elif line.strip().startswith("Kernel driver in use:") and current:
                current["active_module"] = line.split(":")[-1].strip()
            elif line.strip().startswith("Kernel modules:") and current:
                current["modules"] = [m.strip() for m in line.split(":")[-1].split(",")]
        if current:
            devices.append(current)
        return devices

    def _detect_pci_sysfs(self) -> list[dict]:
        """Fallback PCI detection via sysfs."""
        devices = []
        pci_path = "/sys/bus/pci/devices"
        if not os.path.isdir(pci_path):
            return devices
        for dev in os.listdir(pci_path):
            dev_path = os.path.join(pci_path, dev)
            try:
                with open(os.path.join(dev_path, "uevent")) as f:
                    uevent = dict(line.split("=", 1) for line in f.read().strip().split("\n") if "=" in line)
                devices.append({
                    "slot": dev,
                    "description": uevent.get("PCI_ID", ""),
                    "modules": [],
                })
            except (OSError, ValueError):
                pass
        return devices

    def _parse_lsusb(self, output: str) -> list[dict]:
        """Parse lsusb -v output."""
        devices = []
        current = None
        for line in output.strip().split("\n"):
            if line.startswith("Bus ") and "Device" in line:
                if current:
                    devices.append(current)
                current = {"description": line.strip(), "interfaces": []}
            elif current and "bInterfaceClass" in line:
                current["interfaces"].append(line.strip())
        if current:
            devices.append(current)
        return devices

    def _detect_usb_sysfs(self) -> list[dict]:
        """Fallback USB detection via sysfs."""
        devices = []
        usb_path = "/sys/bus/usb/devices"
        if not os.path.isdir(usb_path):
            return devices
        for dev in os.listdir(usb_path):
            if ":" in dev:
                continue
            dev_path = os.path.join(usb_path, dev)
            try:
                with open(os.path.join(dev_path, "product")) as f:
                    product = f.read().strip()
                devices.append({"description": product, "interfaces": []})
            except OSError:
                pass
        return devices

    def get_loaded_modules(self) -> list[dict]:
        """Get currently loaded kernel modules."""
        modules = []
        try:
            with open("/proc/modules") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 4:
                        modules.append({
                            "name": parts[0],
                            "size": int(parts[1]),
                            "used": int(parts[2]) > 0,
                            "dependencies": parts[3].split(",") if parts[3] != "-" else [],
                        })
        except OSError:
            pass
        return modules

    def find_driver_files(self, module_name: str) -> list[str]:
        """Find .ko files for a kernel module."""
        kernel = subprocess.run(
            ["uname", "-r"], capture_output=True, text=True
        ).stdout.strip()

        search_paths = [
            f"/lib/modules/{kernel}/kernel/drivers",
            f"/lib/modules/{kernel}/kernel/net",
            f"/lib/modules/{kernel}/kernel/sound",
            f"/lib/modules/{kernel}/extra",
            f"/lib/modules/{kernel}/updates",
        ]

        found = []
        for search_dir in search_paths:
            if not os.path.isdir(search_dir):
                continue
            for root, dirs, files in os.walk(search_dir):
                for f in files:
                    if f == f"{module_name}.ko" or f == f"{module_name}.ko.xz" or f == f"{module_name}.ko.zst":
                        found.append(os.path.join(root, f))
        return found

    def find_firmware(self, module_name: str) -> list[str]:
        """Find firmware files associated with a module."""
        firmware_files = []
        firmware_dir = "/lib/firmware"
        if not os.path.isdir(firmware_dir):
            return firmware_files

        # Check module's firmware request file
        kernel = subprocess.run(
            ["uname", "-r"], capture_output=True, text=True
        ).stdout.strip()

        modinfo_path = f"/sys/module/{module_name}/firmware"
        if os.path.isdir(modinfo_path):
            for fw in os.listdir(modinfo_path):
                fw_path = os.path.join(firmware_dir, fw)
                if os.path.exists(fw_path):
                    firmware_files.append(fw_path)

        return firmware_files

    def classify_driver(self, module_name: str) -> str:
        """Classify a driver by type based on module name."""
        for dtype, modules in self.DRIVER_TYPES.items():
            if module_name in modules or any(m in module_name for m in modules):
                return dtype
        return "other"

    def dump_all(self, include_firmware: bool = True) -> DriverDumpManifest:
        """
        Full driver dump: detect hardware, extract drivers, package.

        This is the main cross-chain entry point.
        """
        import datetime

        print("[DriverDump] Starting full driver dump...")

        # Get system info
        kernel = subprocess.run(["uname", "-r"], capture_output=True, text=True).stdout.strip()
        arch = subprocess.run(["uname", "-m"], capture_output=True, text=True).stdout.strip()

        self.manifest.source_kernel = kernel
        self.manifest.source_arch = arch
        self.manifest.source_distro = self._detect_distro()
        self.manifest.dump_time = datetime.datetime.now().isoformat()

        # Detect hardware
        print("[DriverDump] Detecting hardware...")
        hw = self.detect_hardware()

        # Get loaded modules
        print("[DriverDump] Scanning loaded modules...")
        loaded = self.get_loaded_modules()
        loaded_names = {m["name"] for m in loaded}

        # Map hardware to modules
        required_modules = set()
        for pci_dev in hw["pci"]:
            if "active_module" in pci_dev:
                required_modules.add(pci_dev["active_module"])
            for mod in pci_dev.get("modules", []):
                required_modules.add(mod)

        # Add essential modules
        essentials = [
            "ext4", "vfat", "ntfs3", "fuse",  # Filesystems
            "xhci_hcd", "ehci_hcd", "usbhid",  # USB
            "ahci", "nvme", "sd_mod",  # Storage
            "evdev", "libps2",  # Input
            "i915", "amdgpu", "nouveau",  # GPU (try all)
            "cfg80211", "mac80211",  # WiFi stack
        ]
        required_modules.update(essentials)

        # Add dependencies
        for mod in loaded:
            if mod["name"] in required_modules:
                for dep in mod["dependencies"]:
                    if dep:
                        required_modules.add(dep)

        # Extract driver files
        print(f"[DriverDump] Extracting {len(required_modules)} drivers...")
        os.makedirs(self.output_dir, exist_ok=True)
        os.makedirs(os.path.join(self.output_dir, "modules"), exist_ok=True)
        if include_firmware:
            os.makedirs(os.path.join(self.output_dir, "firmware"), exist_ok=True)

        for mod_name in required_modules:
            # Find .ko file
            ko_files = self.find_driver_files(mod_name)
            if not ko_files:
                continue

            # Copy to output
            for ko_path in ko_files:
                dest = os.path.join(self.output_dir, "modules", os.path.basename(ko_path))
                shutil.copy2(ko_path, dest)

                stat = os.stat(ko_path)
                driver_info = DriverInfo(
                    name=mod_name,
                    module=mod_name,
                    path=ko_path,
                    type=self.classify_driver(mod_name),
                    dependencies=[d for d in loaded_names if mod_name in d],
                    size_bytes=stat.st_size,
                    loaded=mod_name in loaded_names,
                )

                # Find firmware
                if include_firmware:
                    fw_files = self.find_firmware(mod_name)
                    for fw in fw_files:
                        fw_dest = os.path.join(self.output_dir, "firmware", os.path.basename(fw))
                        if not os.path.exists(fw_dest):
                            shutil.copy2(fw, fw_dest)
                        driver_info.firmware_files.append(os.path.basename(fw))

                self.manifest.drivers.append(driver_info)
                self.manifest.total_size += stat.st_size

        # Save manifest
        manifest_path = os.path.join(self.output_dir, "manifest.json")
        with open(manifest_path, "w") as f:
            json.dump(asdict(self.manifest), f, indent=2)

        print(f"[DriverDump] Done. {len(self.manifest.drivers)} drivers, "
              f"{self.manifest.total_size / 1024 / 1024:.1f}MB total")
        print(f"[DriverDump] Manifest: {manifest_path}")

        return self.manifest

    def dump_specific(self, modules: list[str], include_firmware: bool = True) -> DriverDumpManifest:
        """Dump only specific modules (for targeted driver inclusion)."""
        import datetime

        kernel = subprocess.run(["uname", "-r"], capture_output=True, text=True).stdout.strip()
        self.manifest.source_kernel = kernel
        self.manifest.source_arch = subprocess.run(["uname", "-m"], capture_output=True, text=True).stdout.strip()
        self.manifest.source_distro = self._detect_distro()
        self.manifest.dump_time = datetime.datetime.now().isoformat()

        os.makedirs(os.path.join(self.output_dir, "modules"), exist_ok=True)
        if include_firmware:
            os.makedirs(os.path.join(self.output_dir, "firmware"), exist_ok=True)

        for mod_name in modules:
            ko_files = self.find_driver_files(mod_name)
            for ko_path in ko_files:
                dest = os.path.join(self.output_dir, "modules", os.path.basename(ko_path))
                shutil.copy2(ko_path, dest)

                stat = os.stat(ko_path)
                self.manifest.drivers.append(DriverInfo(
                    name=mod_name, module=mod_name, path=ko_path,
                    type=self.classify_driver(mod_name),
                    size_bytes=stat.st_size,
                    loaded=mod_name in {m["name"] for m in self.get_loaded_modules()},
                ))

        # Save manifest
        manifest_path = os.path.join(self.output_dir, "manifest.json")
        with open(manifest_path, "w") as f:
            json.dump(asdict(self.manifest), f, indent=2)

        return self.manifest

    def _detect_distro(self) -> str:
        """Detect Linux distribution."""
        try:
            with open("/etc/os-release") as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        return line.split("=", 1)[1].strip().strip('"')
        except OSError:
            pass
        return "Unknown"
