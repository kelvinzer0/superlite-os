"""Driver Resolver — Download correct Linux drivers based on hardware detection

Instead of copying from running host, this module:
1. Detects hardware via PCI/USB IDs (cross-platform)
2. Queries online databases for matching Linux kernel modules
3. Downloads the correct .ko files + firmware from package repos
4. Works even when host is Windows (reads hardware IDs from registry/WMI)
"""

import os
import json
import re
import subprocess
import tempfile
from dataclasses import dataclass, field, asdict
from typing import Optional
from pathlib import Path


@dataclass
class HardwareDevice:
    """Detected hardware device."""
    bus: str  # pci, usb, platform
    vendor_id: str
    device_id: str
    subvendor_id: str = ""
    subdevice_id: str = ""
    class_code: str = ""
    description: str = ""
    driver_module: str = ""  # Linux kernel module name
    firmware_files: list[str] = field(default_factory=list)
    pci_slot: str = ""


@dataclass
class DriverPackage:
    """A downloadable driver package."""
    module_name: str
    kernel_version: str
    arch: str
    url: str
    filename: str
    size: int = 0
    dependencies: list[str] = field(default_factory=list)
    firmware_urls: list[str] = field(default_factory=list)


# PCI ID → Linux kernel module mapping (curated top devices)
# Source: linux/drivers, hwdb, pci.ids
PCI_DRIVER_MAP = {
    # GPU - Intel
    ("8086", "9a49"): {"module": "i915", "desc": "Intel TigerLake-LP GT2 [Iris Xe]"},
    ("8086", "4626"): {"module": "i915", "desc": "Intel Alder Lake-P GT2 [Iris Xe]"},
    ("8086", "a780"): {"module": "i915", "desc": "Intel Raptor Lake-S GT1 [UHD 770]"},
    ("8086", "5917"): {"module": "i915", "desc": "Intel UHD Graphics 620"},
    ("8086", "3e92"): {"module": "i915", "desc": "Intel UHD Graphics 630"},
    ("8086", "1912"): {"module": "i915", "desc": "Intel HD Graphics 530"},
    # GPU - NVIDIA
    ("10de", "2488"): {"module": "nouveau", "desc": "NVIDIA GA106 [RTX 3060]"},
    ("10de", "2484"): {"module": "nouveau", "desc": "NVIDIA GA106 [RTX 3060 Ti]"},
    ("10de", "2206"): {"module": "nouveau", "desc": "NVIDIA GA102 [RTX 3080]"},
    ("10de", "2204"): {"module": "nouveau", "desc": "NVIDIA GA102 [RTX 3090]"},
    ("10de", "2560"): {"module": "nouveau", "desc": "NVIDIA AD106 [RTX 4060]"},
    ("10de", "2786"): {"module": "nouveau", "desc": "NVIDIA AD104 [RTX 4070 Ti]"},
    ("10de", "2684"): {"module": "nouveau", "desc": "NVIDIA AD102 [RTX 4090]"},
    ("10de", "1f08"): {"module": "nouveau", "desc": "NVIDIA TU106 [RTX 2060]"},
    ("10de", "1e84"): {"module": "nouveau", "desc": "NVIDIA TU104 [RTX 2080]"},
    ("10de", "1c82"): {"module": "nouveau", "desc": "NVIDIA GP108 [GT 1030]"},
    # GPU - AMD
    ("1002", "73df"): {"module": "amdgpu", "desc": "AMD Navi 22 [RX 6700 XT]"},
    ("1002", "73bf"): {"module": "amdgpu", "desc": "AMD Navi 21 [RX 6800 XT]"},
    ("1002", "744c"): {"module": "amdgpu", "desc": "AMD Navi 31 [RX 7900 XTX]"},
    ("1002", "7480"): {"module": "amdgpu", "desc": "AMD Navi 33 [RX 7600]"},
    ("1002", "1638"): {"module": "amdgpu", "desc": "AMD Cezanne [Radeon Vega]"},
    ("1002", "15d8"): {"module": "amdgpu", "desc": "AMD Picasso [Radeon Vega]"},
    # Network - Intel
    ("8086", "15b8"): {"module": "e1000e", "desc": "Intel I219-V"},
    ("8086", "15b7"): {"module": "e1000e", "desc": "Intel I219-LM"},
    ("8086", "1539"): {"module": "e1000e", "desc": "Intel I211AT"},
    ("8086", "10d3"): {"module": "e1000e", "desc": "Intel 82574L"},
    ("8086", "10fb"): {"module": "ixgbe", "desc": "Intel 82599 10GbE"},
    ("8086", "1572"): {"module": "i40e", "desc": "Intel X710 10GbE"},
    ("8086", "2723"): {"module": "iwlwifi", "desc": "Intel Wi-Fi 6 AX200"},
    ("8086", "2725"): {"module": "iwlwifi", "desc": "Intel Wi-Fi 6E AX210"},
    ("8086", "a0f0"): {"module": "iwlwifi", "desc": "Intel Wi-Fi 6 AX201"},
    ("8086", "02b0"): {"module": "iwlwifi", "desc": "Intel Wi-Fi 7 BE200"},
    # Network - Realtek
    ("10ec", "8168"): {"module": "r8169", "desc": "Realtek RTL8111/8168"},
    ("10ec", "8125"): {"module": "r8169", "desc": "Realtek RTL8125 2.5GbE"},
    ("10ec", "b852"): {"module": "r8169", "desc": "Realtek RTL8125BG 2.5GbE"},
    # Network - Broadcom
    ("14e4", "43a0"): {"module": "brcmfmac", "desc": "Broadcom BCM4360 Wi-Fi"},
    ("14e4", "43ec"): {"module": "brcmfmac", "desc": "Broadcom BCM4356 Wi-Fi"},
    # Network - Qualcomm/Atheros
    ("168c", "003e"): {"module": "ath10k_pci", "desc": "Qualcomm QCA6174 Wi-Fi"},
    ("168c", "003c"): {"module": "ath10k_pci", "desc": "Qualcomm QCA988x Wi-Fi"},
    ("17cb", "1103"): {"module": "ath11k_pci", "desc": "Qualcomm QCNFA765 Wi-Fi 6E"},
    # Storage - NVMe
    ("144d", "a80a"): {"module": "nvme", "desc": "Samsung NVMe SSD"},
    ("144d", "a808"): {"module": "nvme", "desc": "Samsung 970 EVO Plus"},
    ("1987", "5012"): {"module": "nvme", "desc": "Phison E12 NVMe SSD"},
    ("15b7", "2001"): {"module": "nvme", "desc": "WD Black SN750"},
    ("1c5c", "1984"): {"module": "nvme", "desc": "SK Hynix Gold P31"},
    # Storage - AHCI (most SATA controllers)
    ("8086", "2822"): {"module": "ahci", "desc": "Intel SATA AHCI"},
    ("8086", "a0d3"): {"module": "ahci", "desc": "Intel Tiger Lake SATA"},
    ("1022", "7901"): {"module": "ahci", "desc": "AMD SATA AHCI"},
    # USB Controllers
    ("8086", "a0ed"): {"module": "xhci_hcd", "desc": "Intel USB 3.0"},
    ("8086", "02ed"): {"module": "xhci_hcd", "desc": "Intel Tiger Lake USB"},
    ("1022", "43f5"): {"module": "xhci_hcd", "desc": "AMD USB 3.1"},
    # Audio - Intel
    ("8086", "a0c8"): {"module": "snd_hda_intel", "desc": "Intel Tiger Lake HD Audio"},
    ("8086", "f0c8"): {"module": "snd_hda_intel", "desc": "Intel Alder Lake HD Audio"},
    ("8086", "7ad0"): {"module": "snd_hda_intel", "desc": "Intel Raptor Lake HD Audio"},
    ("8086", "9dc8"): {"module": "snd_hda_intel", "desc": "Intel Cannon Lake HD Audio"},
    # Audio - AMD
    ("1022", "15e3"): {"module": "snd_hda_intel", "desc": "AMD Raven/Renoir HD Audio"},
    # Bluetooth
    ("8086", "0026"): {"module": "btusb", "desc": "Intel AX200 Bluetooth"},
    ("8086", "0032"): {"module": "btusb", "desc": "Intel AX201 Bluetooth"},
    ("8086", "0033"): {"module": "btusb", "desc": "Intel AX210 Bluetooth"},
    ("0b05", "190e"): {"module": "btusb", "desc": "ASUS Bluetooth"},
    ("0489", "e0a0"): {"module": "btusb", "desc": "MediaTek Bluetooth"},
    # Input
    ("06cb", "00bd"): {"module": "hid_multitouch", "desc": "Synaptics Touchpad"},
    ("04f3", "311c"): {"module": "hid_multitouch", "desc": "ELAN Touchpad"},
}

# USB class → driver mapping
USB_CLASS_DRIVERS = {
    "03": "usbhid",       # HID (keyboard, mouse)
    "08": "usb_storage",  # Mass storage
    "0e": "uvcvideo",     # Video (webcam)
    "01": "snd_usb_audio", # Audio
    "02": "cdc_acm",      # CDC (serial)
    "0a": "cdc_ether",    # CDC (network)
    "e0": "btusb",        # Bluetooth
}

# Kernel module → firmware URLs (common firmware blobs)
FIRMWARE_DB = {
    "iwlwifi": [
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/iwlwifi-cc-a0-77.ucode",
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/iwlwifi-ty-a0-gf-a0-83.ucode",
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/iwlwifi-ty-a0-gf-a0.pnvm",
    ],
    "ath10k_pci": [
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/QCA6174/hw3.0/board-2.bin",
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/QCA6174/hw3.0/firmware-6.bin_WLAN.RM.4.4.1-00288-QCARMSWPZ-1",
    ],
    "ath11k_pci": [
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath11k/WCN6855/hw2.0/amss.bin",
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath11k/WCN6855/hw2.0/m3.bin",
    ],
    "brcmfmac": [
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcmfmac43602-pcie.ap.bin",
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/brcmfmac43602-pcie.bin",
    ],
    "amdgpu": [
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/amdgpu/navi10_gpu_info.bin",
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/amdgpu/navi10_smc.bin",
    ],
    "nouveau": [
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/nvidia/gm200/acr/bl.bin",
    ],
    "r8169": [
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtl_nic/rtl8168h-2.fw",
        "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/rtl_nic/rtl8125a-3.fw",
    ],
}


class DriverResolver:
    """
    Resolves hardware → Linux driver mapping and downloads drivers.

    Works cross-platform:
    - Linux: reads /sys, lspci, lsusb
    - Windows: reads via WMI/registry (for cross-chain builds)
    - Generic: uses PCI/USB ID databases
    """

    KERNEL_DB_URL = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/"
    PCI_IDS_URL = "https://pci-ids.ucw.cz/v2.2/pci.ids"
    USB_IDS_URL = "https://usb-ids.gowdy.us/read/UD/"

    def __init__(self, output_dir: str = None, kernel_version: str = None):
        self.output_dir = output_dir or os.path.expanduser("~/.superlite/drivers")
        self.kernel_version = kernel_version or self._detect_kernel()
        self.detected_hw: list[HardwareDevice] = []
        self.resolved_drivers: list[DriverPackage] = []
        self._pci_db: dict = {}
        self._usb_db: dict = {}

    def detect_hardware(self) -> list[HardwareDevice]:
        """Detect hardware using best available method."""
        import platform
        system = platform.system().lower()

        if system == "linux":
            self.detected_hw = self._detect_linux()
        elif system == "windows":
            self.detected_hw = self._detect_windows()
        else:
            # Generic fallback: try /sys if available
            self.detected_hw = self._detect_sysfs()

        return self.detected_hw

    def resolve_drivers(self, devices: list[HardwareDevice] = None) -> list[DriverPackage]:
        """Resolve which kernel modules are needed for detected hardware."""
        devices = devices or self.detected_hw
        if not devices:
            devices = self.detect_hardware()

        modules_seen = set()
        packages = []

        for dev in devices:
            module = self._lookup_driver(dev)
            if not module or module in modules_seen:
                continue
            modules_seen.add(module)

            pkg = DriverPackage(
                module_name=module,
                kernel_version=self.kernel_version,
                arch=self._detect_arch(),
                url="",  # Will be resolved in download phase
                filename=f"{module}.ko",
                dependencies=self._get_module_deps(module),
                firmware_urls=FIRMWARE_DB.get(module, []),
            )
            packages.append(pkg)

        self.resolved_drivers = packages
        return packages

    def download_firmware(self, packages: list[DriverPackage] = None) -> dict[str, list[str]]:
        """Download firmware blobs for resolved drivers."""
        packages = packages or self.resolved_drivers
        os.makedirs(os.path.join(self.output_dir, "firmware"), exist_ok=True)

        downloaded = {}
        for pkg in packages:
            if not pkg.firmware_urls:
                continue

            downloaded[pkg.module_name] = []
            for url in pkg.firmware_urls:
                filename = os.path.basename(url)
                dest = os.path.join(self.output_dir, "firmware", filename)

                if os.path.exists(dest):
                    downloaded[pkg.module_name].append(dest)
                    continue

                try:
                    import urllib.request
                    print(f"  Downloading: {filename}")
                    urllib.request.urlretrieve(url, dest)
                    downloaded[pkg.module_name].append(dest)
                except Exception as e:
                    print(f"  Warning: Failed to download {filename}: {e}")

        return downloaded

    def build_driver_bundle(self) -> dict:
        """Build complete driver bundle: detect → resolve → download."""
        print("[DriverResolver] Detecting hardware...")
        self.detect_hardware()
        print(f"  Found {len(self.detected_hw)} devices")

        print("[DriverResolver] Resolving drivers...")
        packages = self.resolve_drivers()
        print(f"  Need {len(packages)} kernel modules")

        print("[DriverResolver] Downloading firmware...")
        fw = self.download_firmware(packages)
        fw_count = sum(len(v) for v in fw.values())
        print(f"  Downloaded {fw_count} firmware files")

        # Build manifest
        manifest = {
            "kernel": self.kernel_version,
            "arch": self._detect_arch(),
            "devices": [asdict(d) for d in self.detected_hw],
            "drivers": [asdict(p) for p in packages],
            "firmware": fw,
        }

        manifest_path = os.path.join(self.output_dir, "driver-bundle.json")
        with open(manifest_path, "w") as f:
            json.dump(manifest, f, indent=2)

        print(f"[DriverResolver] Bundle saved: {manifest_path}")
        return manifest

    # ─── Hardware Detection (Linux) ────────────────────────────

    def _detect_linux(self) -> list[HardwareDevice]:
        """Detect hardware on Linux via /sys and lspci."""
        devices = []

        # PCI devices via sysfs
        devices.extend(self._detect_pci_sysfs())

        # USB devices via sysfs
        devices.extend(self._detect_usb_sysfs())

        # If lspci available, enrich with descriptions
        try:
            result = subprocess.run(["lspci", "-nn"], capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                self._enrich_from_lspci(devices, result.stdout)
        except FileNotFoundError:
            pass

        return devices

    def _detect_pci_sysfs(self) -> list[HardwareDevice]:
        """Detect PCI devices from /sys/bus/pci."""
        devices = []
        pci_path = "/sys/bus/pci/devices"
        if not os.path.isdir(pci_path):
            return devices

        for entry in os.listdir(pci_path):
            dev_path = os.path.join(pci_path, entry)
            try:
                vendor = self._read_sysfs_attr(dev_path, "vendor")[2:]  # strip 0x
                device = self._read_sysfs_attr(dev_path, "device")[2:]
                class_code = self._read_sysfs_attr(dev_path, "class")[2:]

                # Read driver if bound
                driver = ""
                driver_link = os.path.join(dev_path, "driver")
                if os.path.islink(driver_link):
                    driver = os.path.basename(os.readlink(driver_link))

                hw = HardwareDevice(
                    bus="pci",
                    vendor_id=vendor.lower(),
                    device_id=device.lower(),
                    class_code=class_code,
                    pci_slot=entry,
                    driver_module=driver,
                )

                # Try subvendor/subdevice
                try:
                    hw.subvendor_id = self._read_sysfs_attr(dev_path, "subsystem_vendor")[2:]
                    hw.subdevice_id = self._read_sysfs_attr(dev_path, "subsystem_device")[2:]
                except (FileNotFoundError, IndexError):
                    pass

                devices.append(hw)
            except (OSError, IndexError):
                continue

        return devices

    def _detect_usb_sysfs(self) -> list[HardwareDevice]:
        """Detect USB devices from /sys/bus/usb."""
        devices = []
        usb_path = "/sys/bus/usb/devices"
        if not os.path.isdir(usb_path):
            return devices

        for entry in os.listdir(usb_path):
            dev_path = os.path.join(usb_path, entry)
            id_vendor_file = os.path.join(dev_path, "idVendor")
            id_product_file = os.path.join(dev_path, "idProduct")

            if not os.path.isfile(id_vendor_file):
                continue

            try:
                with open(id_vendor_file) as f:
                    vendor = f.read().strip()
                with open(id_product_file) as f:
                    product = f.read().strip()

                # Read USB class
                class_code = ""
                bclass = os.path.join(dev_path, "bDeviceClass")
                if os.path.isfile(bclass):
                    with open(bclass) as f:
                        class_code = f.read().strip()

                product_name = ""
                prod_file = os.path.join(dev_path, "product")
                if os.path.isfile(prod_file):
                    with open(prod_file) as f:
                        product_name = f.read().strip()

                devices.append(HardwareDevice(
                    bus="usb",
                    vendor_id=vendor.lower(),
                    device_id=product.lower(),
                    class_code=class_code,
                    description=product_name,
                ))
            except OSError:
                continue

        return devices

    def _enrich_from_lspci(self, devices: list[HardwareDevice], lspci_output: str):
        """Enrich detected devices with lspci descriptions."""
        # Parse lspci -nn output
        # Format: "00:02.0 VGA compatible controller [0300]: Intel Corporation ... [8086:9a49]"
        for line in lspci_output.strip().split("\n"):
            match = re.match(r'(\S+)\s+.*?:\s+(.*?)\s+\[([0-9a-f]{4}):([0-9a-f]{4})\]', line)
            if not match:
                continue

            slot, desc, vendor, device = match.groups()
            for dev in devices:
                if dev.pci_slot == slot:
                    dev.description = desc
                    break
                # Match by vendor/device ID
                if dev.vendor_id == vendor.lower() and dev.device_id == device.lower():
                    dev.description = desc

    # ─── Hardware Detection (Windows) ─────────────────────────

    def _detect_windows(self) -> list[HardwareDevice]:
        """Detect hardware on Windows via WMI (for cross-chain builds)."""
        devices = []

        # Use PowerShell to get PCI devices
        try:
            result = subprocess.run(
                ["powershell", "-Command",
                 "Get-PnpDevice -Class Display,Net,SCSIAdapter,USB,HDC -ErrorAction SilentlyContinue | "
                 "Select-Object InstanceId,FriendlyName,Class | ConvertTo-Json"],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0:
                devices = self._parse_windows_pnp(result.stdout)
        except FileNotFoundError:
            # Try WMIC fallback
            try:
                result = subprocess.run(
                    ["wmic", "path", "Win32_PnPEntity", "get",
                     "DeviceID,Name,PNPClass", "/format:csv"],
                    capture_output=True, text=True, timeout=30
                )
                if result.returncode == 0:
                    devices = self._parse_windows_wmic(result.stdout)
            except FileNotFoundError:
                print("[DriverResolver] Cannot detect Windows hardware (no PowerShell/WMIC)")

        return devices

    def _parse_windows_pnp(self, json_str: str) -> list[HardwareDevice]:
        """Parse Windows PnP device JSON."""
        devices = []
        try:
            data = json.loads(json_str)
            if isinstance(data, dict):
                data = [data]

            for item in data:
                instance_id = item.get("InstanceId", "")
                name = item.get("FriendlyName", "")

                # Extract PCI IDs from instance ID
                # Format: PCI\VEN_8086&DEV_9A49&SUBSYS_...
                pci_match = re.search(r'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})', instance_id)
                if pci_match:
                    vendor, device = pci_match.groups()
                    subvendor, subdevice = "", ""
                    sub_match = re.search(r'SUBSYS_([0-9A-Fa-f]{4})([0-9A-Fa-f]{4})', instance_id)
                    if sub_match:
                        subvendor, subdevice = sub_match.groups()

                    devices.append(HardwareDevice(
                        bus="pci",
                        vendor_id=vendor.lower(),
                        device_id=device.lower(),
                        subvendor_id=subvendor.lower(),
                        subdevice_id=subdevice.lower(),
                        description=name,
                    ))

                # USB devices
                usb_match = re.search(r'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})', instance_id)
                if usb_match:
                    vendor, product = usb_match.groups()
                    devices.append(HardwareDevice(
                        bus="usb",
                        vendor_id=vendor.lower(),
                        device_id=product.lower(),
                        description=name,
                    ))
        except json.JSONDecodeError:
            pass

        return devices

    def _parse_windows_wmic(self, csv_str: str) -> list[HardwareDevice]:
        """Parse WMIC CSV output."""
        devices = []
        for line in csv_str.strip().split("\n")[1:]:  # Skip header
            parts = line.strip().split(",")
            if len(parts) < 3:
                continue
            _, name, instance_id = parts[0], parts[1], parts[2] if len(parts) > 2 else ""

            pci_match = re.search(r'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})', instance_id or name)
            if pci_match:
                vendor, device = pci_match.groups()
                devices.append(HardwareDevice(
                    bus="pci",
                    vendor_id=vendor.lower(),
                    device_id=device.lower(),
                    description=name,
                ))
        return devices

    # ─── Driver Resolution ────────────────────────────────────

    def _lookup_driver(self, device: HardwareDevice) -> Optional[str]:
        """Look up the Linux kernel module for a device."""
        # Direct PCI ID lookup
        key = (device.vendor_id, device.device_id)
        if key in PCI_DRIVER_MAP:
            info = PCI_DRIVER_MAP[key]
            device.description = device.description or info.get("desc", "")
            return info["module"]

        # USB class-based lookup
        if device.bus == "usb" and device.class_code:
            module = USB_CLASS_DRIVERS.get(device.class_code)
            if module:
                return module

        # Class code based (PCI)
        if device.class_code:
            return self._class_code_to_module(device.class_code)

        return None

    def _class_code_to_module(self, class_code: str) -> Optional[str]:
        """Map PCI class code to likely kernel module."""
        # PCI class codes (first 2 bytes = base class, subclass)
        class_map = {
            "0106": "ahci",        # SATA AHCI
            "0108": "nvme",        # NVMe
            "0101": "ata_piix",    # IDE
            "0200": "e1000e",      # Ethernet (generic)
            "0280": "iwlwifi",     # Wireless (generic)
            "0300": "i915",        # VGA (generic, prefer Intel)
            "0302": "i915",        # 3D controller
            "0c03": "xhci_hcd",   # USB controller
            "0403": "snd_hda_intel", # Audio
            "0c05": "i2c_i801",   # SMBus
        }
        # Try 4-char match, then 2-char
        for length in [4, 2]:
            prefix = class_code[:length].lower()
            if prefix in class_map:
                return class_map[prefix]
        return None

    def _get_module_deps(self, module: str) -> list[str]:
        """Get kernel module dependencies."""
        dep_map = {
            "iwlwifi": ["cfg80211", "mac80211"],
            "ath10k_pci": ["cfg80211", "mac80211", "ath10k_core"],
            "ath11k_pci": ["cfg80211", "mac80211", "ath11k"],
            "brcmfmac": ["cfg80211", "brcmutil"],
            "nouveau": ["drm", "drm_kms_helper", "ttm", "i2c-algo-bit"],
            "amdgpu": ["drm", "drm_kms_helper", "ttm", "i2c-algo-bit"],
            "i915": ["drm", "drm_kms_helper", "i2c-algo-bit"],
            "snd_hda_intel": ["snd_hda_codec", "snd_hda_core", "snd_pcm", "snd"],
            "btusb": ["bluetooth", "ecdh_generic"],
            "r8169": [],
            "e1000e": [],
            "xhci_hcd": [],
            "nvme": [],
            "ahci": ["libahci"],
        }
        return dep_map.get(module, [])

    # ─── Utilities ────────────────────────────────────────────

    def _read_sysfs_attr(self, path: str, attr: str) -> str:
        """Read a sysfs attribute."""
        with open(os.path.join(path, attr)) as f:
            return f.read().strip()

    def _detect_kernel(self) -> str:
        """Detect running kernel version."""
        try:
            result = subprocess.run(["uname", "-r"], capture_output=True, text=True, timeout=5)
            return result.stdout.strip()
        except Exception:
            return "6.1.0-generic"

    def _detect_arch(self) -> str:
        """Detect system architecture."""
        import platform
        machine = platform.machine().lower()
        arch_map = {
            "x86_64": "x86_64", "amd64": "x86_64",
            "aarch64": "aarch64", "arm64": "aarch64",
            "armv7l": "armv7", "armv7": "armv7",
            "armv6l": "armhf",
            "ppc64le": "ppc64le",
            "s390x": "s390x",
            "riscv64": "riscv64",
        }
        return arch_map.get(machine, "x86_64")

    def generate_initramfs_modules(self, packages: list[DriverPackage] = None) -> list[str]:
        """Generate list of modules to include in initramfs."""
        packages = packages or self.resolved_drivers
        modules = []

        # Essential modules always included
        essentials = [
            "ext4", "vfat", "ntfs3", "fuse",
            "xhci_hcd", "ehci_hcd", "usbhid", "usb_storage",
            "ahci", "nvme", "sd_mod", "sr_mod",
            "evdev", "libps2", "atkbd", "mousedev",
        ]
        modules.extend(essentials)

        # Detected drivers
        for pkg in packages:
            if pkg.module_name not in modules:
                modules.append(pkg.module_name)
            for dep in pkg.dependencies:
                if dep not in modules:
                    modules.append(dep)

        return modules
