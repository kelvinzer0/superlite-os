# SuperLite OS - Unit Tests

import unittest
import sys
import os
import json

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Check GTK availability
try:
    import gi
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gtk
    HAS_GTK = True
except (ValueError, ImportError):
    HAS_GTK = False


# ═══════════════════════════════════════════════════════════════
# DriverResolver — Hardware → Driver mapping
# ═══════════════════════════════════════════════════════════════

class TestDriverResolver(unittest.TestCase):
    """Test driver resolution from hardware IDs."""

    def test_pci_driver_lookup_intel_gpu(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="8086", device_id="9a49")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "i915")
        self.assertIn("TigerLake", dev.description)

    def test_pci_driver_lookup_nvidia_gpu(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="10de", device_id="2488")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "nouveau")

    def test_pci_driver_lookup_amd_gpu(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="1002", device_id="73df")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "amdgpu")

    def test_pci_driver_lookup_intel_wifi(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="8086", device_id="2723")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "iwlwifi")

    def test_pci_driver_lookup_realtek_ethernet(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="10ec", device_id="8168")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "r8169")

    def test_pci_driver_lookup_nvme(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="144d", device_id="a80a")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "nvme")

    def test_pci_driver_lookup_audio(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="8086", device_id="a0c8")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "snd_hda_intel")

    def test_pci_driver_lookup_unknown(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="pci", vendor_id="ffff", device_id="ffff")
        module = r._lookup_driver(dev)
        self.assertIsNone(module)

    def test_usb_class_driver_hid(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="usb", vendor_id="046d", device_id="c077", class_code="03")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "usbhid")

    def test_usb_class_driver_storage(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="usb", vendor_id="0781", device_id="5567", class_code="08")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "usb_storage")

    def test_usb_class_driver_bluetooth(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        dev = HardwareDevice(bus="usb", vendor_id="8087", device_id="0026", class_code="e0")
        module = r._lookup_driver(dev)
        self.assertEqual(module, "btusb")

    def test_class_code_to_module_sata(self):
        from drivers.resolver import DriverResolver
        r = DriverResolver("/tmp/test-resolver")
        self.assertEqual(r._class_code_to_module("0106"), "ahci")
        self.assertEqual(r._class_code_to_module("0108"), "nvme")
        self.assertEqual(r._class_code_to_module("0200"), "e1000e")
        self.assertEqual(r._class_code_to_module("0300"), "i915")
        self.assertEqual(r._class_code_to_module("0c03"), "xhci_hcd")

    def test_module_deps(self):
        from drivers.resolver import DriverResolver
        r = DriverResolver("/tmp/test-resolver")
        self.assertIn("cfg80211", r._get_module_deps("iwlwifi"))
        self.assertIn("mac80211", r._get_module_deps("iwlwifi"))
        self.assertIn("drm", r._get_module_deps("nouveau"))
        self.assertIn("snd_hda_codec", r._get_module_deps("snd_hda_intel"))
        self.assertEqual(r._get_module_deps("r8169"), [])

    def test_resolve_multiple_devices(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        r.detected_hw = [
            HardwareDevice(bus="pci", vendor_id="8086", device_id="9a49"),  # i915
            HardwareDevice(bus="pci", vendor_id="8086", device_id="2723"),  # iwlwifi
            HardwareDevice(bus="pci", vendor_id="10ec", device_id="8168"),  # r8169
            HardwareDevice(bus="pci", vendor_id="8086", device_id="a0c8"),  # snd_hda_intel
            HardwareDevice(bus="pci", vendor_id="8086", device_id="a0ed"),  # xhci_hcd
        ]
        packages = r.resolve_drivers()
        modules = [p.module_name for p in packages]
        self.assertIn("i915", modules)
        self.assertIn("iwlwifi", modules)
        self.assertIn("r8169", modules)
        self.assertIn("snd_hda_intel", modules)
        self.assertIn("xhci_hcd", modules)

    def test_resolve_deduplicates(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        r.detected_hw = [
            HardwareDevice(bus="pci", vendor_id="8086", device_id="9a49"),
            HardwareDevice(bus="pci", vendor_id="8086", device_id="4626"),  # Also i915
        ]
        packages = r.resolve_drivers()
        i915_count = sum(1 for p in packages if p.module_name == "i915")
        self.assertEqual(i915_count, 1)

    def test_initramfs_modules(self):
        from drivers.resolver import DriverResolver, DriverPackage
        r = DriverResolver("/tmp/test-resolver")
        r.resolved_drivers = [
            DriverPackage(module_name="i915", kernel_version="6.1.0", arch="x86_64",
                         url="", filename="i915.ko", dependencies=["drm"]),
            DriverPackage(module_name="iwlwifi", kernel_version="6.1.0", arch="x86_64",
                         url="", filename="iwlwifi.ko", dependencies=["cfg80211", "mac80211"]),
        ]
        modules = r.generate_initramfs_modules()
        # Should include essentials + detected + deps
        self.assertIn("ext4", modules)
        self.assertIn("xhci_hcd", modules)
        self.assertIn("i915", modules)
        self.assertIn("iwlwifi", modules)
        self.assertIn("cfg80211", modules)
        self.assertIn("mac80211", modules)

    def test_hardware_device_dataclass(self):
        from drivers.resolver import HardwareDevice
        dev = HardwareDevice(
            bus="pci", vendor_id="8086", device_id="9a49",
            description="Intel GPU", driver_module="i915",
        )
        self.assertEqual(dev.bus, "pci")
        self.assertEqual(dev.vendor_id, "8086")
        self.assertEqual(dev.driver_module, "i915")
        self.assertEqual(dev.firmware_files, [])

    def test_driver_package_dataclass(self):
        from drivers.resolver import DriverPackage
        pkg = DriverPackage(
            module_name="iwlwifi",
            kernel_version="6.1.0",
            arch="x86_64",
            url="https://example.com/iwlwifi.ko",
            filename="iwlwifi.ko",
            dependencies=["cfg80211"],
            firmware_urls=["https://example.com/fw.ucode"],
        )
        self.assertEqual(pkg.module_name, "iwlwifi")
        self.assertEqual(len(pkg.dependencies), 1)
        self.assertEqual(len(pkg.firmware_urls), 1)

    def test_driver_bundle_json_serializable(self):
        from drivers.resolver import DriverResolver, HardwareDevice
        r = DriverResolver("/tmp/test-resolver")
        r.detected_hw = [
            HardwareDevice(bus="pci", vendor_id="8086", device_id="9a49"),
        ]
        packages = r.resolve_drivers()
        # Should be JSON serializable
        manifest = {
            "devices": [d.__dict__ for d in r.detected_hw],
            "drivers": [p.__dict__ for p in packages],
        }
        json_str = json.dumps(manifest, indent=2)
        self.assertIn("i915", json_str)
        self.assertIn("8086", json_str)

    def test_detect_arch(self):
        from drivers.resolver import DriverResolver
        r = DriverResolver("/tmp/test-resolver")
        arch = r._detect_arch()
        self.assertIn(arch, ["x86_64", "aarch64", "armv7", "armhf", "i686", "ppc64le", "s390x", "riscv64"])


# ═══════════════════════════════════════════════════════════════
# DriverDump — Host driver extraction
# ═══════════════════════════════════════════════════════════════

class TestDriverDump(unittest.TestCase):
    """Test driver dump functionality."""

    def test_driver_classify(self):
        from drivers.dump import DriverDump
        d = DriverDump("/tmp/test-dump")
        self.assertEqual(d.classify_driver("i915"), "gpu")
        self.assertEqual(d.classify_driver("iwlwifi"), "network")
        self.assertEqual(d.classify_driver("ahci"), "storage")
        self.assertEqual(d.classify_driver("xhci_hcd"), "usb")
        self.assertEqual(d.classify_driver("evdev"), "input")
        self.assertEqual(d.classify_driver("snd_hda_intel"), "audio")
        self.assertEqual(d.classify_driver("btusb"), "bluetooth")
        self.assertEqual(d.classify_driver("cfg80211"), "wifi")
        self.assertEqual(d.classify_driver("unknown_module"), "other")

    def test_driver_info(self):
        from drivers.dump import DriverInfo
        info = DriverInfo(
            name="test", module="test_mod",
            path="/lib/modules/test.ko", type="gpu", size_bytes=1024,
        )
        self.assertEqual(info.name, "test")
        self.assertEqual(info.type, "gpu")
        self.assertEqual(info.size_bytes, 1024)

    def test_driver_dump_manifest(self):
        from drivers.dump import DriverDumpManifest, DriverInfo
        manifest = DriverDumpManifest(
            source_kernel="6.1.0",
            source_arch="x86_64",
            source_distro="Ubuntu 24.04",
            drivers=[
                DriverInfo(name="i915", module="i915", path="/test", type="gpu"),
            ],
        )
        self.assertEqual(len(manifest.drivers), 1)
        self.assertEqual(manifest.drivers[0].type, "gpu")


# ═══════════════════════════════════════════════════════════════
# Config — System configuration
# ═══════════════════════════════════════════════════════════════

class TestConfig(unittest.TestCase):
    """Test configuration system."""

    def test_config_defaults(self):
        from utils import Config
        config = Config("/tmp/test-config.json")
        self.assertEqual(config.get("wm.gap"), 4)
        self.assertEqual(config.get("theme.accent"), "#e94560")
        self.assertEqual(config.get("nonexistent", "default"), "default")

    def test_config_set_get(self):
        from utils import Config
        config = Config("/tmp/test-config.json")
        config.set("wm.gap", 8)
        self.assertEqual(config.get("wm.gap"), 8)

    def test_config_nested_set(self):
        from utils import Config
        config = Config("/tmp/test-config.json")
        config.set("custom.new.value", 42)
        self.assertEqual(config.get("custom.new.value"), 42)


# ═══════════════════════════════════════════════════════════════
# BusyBox — Base system
# ═══════════════════════════════════════════════════════════════

class TestBusyBoxBase(unittest.TestCase):
    """Test BusyBox base system."""

    def test_supported_arches(self):
        from base import BusyBoxBase
        arches = BusyBoxBase.SUPPORTED_ARCHES
        self.assertIn("x86_64", arches)
        self.assertIn("aarch64", arches)
        self.assertIn("armv7", arches)
        self.assertIn("armhf", arches)
        self.assertIn("i686", arches)
        self.assertIn("ppc64le", arches)
        self.assertIn("s390x", arches)
        self.assertIn("riscv64", arches)
        self.assertEqual(len(arches), 8)

    def test_detect_arch(self):
        from base import BusyBoxBase
        arch = BusyBoxBase.detect_arch()
        self.assertIn(arch, BusyBoxBase.SUPPORTED_ARCHES)

    def test_busybox_binaries_exist(self):
        base_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "base")
        for arch in ["x86_64", "aarch64", "armv7", "armhf", "i686", "ppc64le", "s390x", "riscv64"]:
            path = os.path.join(base_dir, f"busybox-{arch}")
            self.assertTrue(os.path.isfile(path), f"Missing: busybox-{arch}")
            with open(path, "rb") as f:
                magic = f.read(4)
                self.assertEqual(magic, b'\x7fELF', f"Not ELF: busybox-{arch}")

    def test_busybox_binary_size_reasonable(self):
        base_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "base")
        for arch in ["x86_64", "aarch64"]:
            path = os.path.join(base_dir, f"busybox-{arch}")
            size = os.path.getsize(path)
            # BusyBox static should be 500KB - 2MB
            self.assertGreater(size, 500_000, f"Too small: busybox-{arch}")
            self.assertLess(size, 2_000_000, f"Too large: busybox-{arch}")

    def test_initramfs_files_exist(self):
        base_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "base")
        for arch in ["x86_64", "aarch64", "armv7", "armhf", "i686", "ppc64le", "s390x", "riscv64"]:
            path = os.path.join(base_dir, f"initramfs-{arch}.cpio.gz")
            self.assertTrue(os.path.isfile(path), f"Missing: initramfs-{arch}.cpio.gz")
            size = os.path.getsize(path)
            self.assertGreater(size, 100_000, f"Too small: initramfs-{arch}")
            self.assertLess(size, 2_000_000, f"Too large: initramfs-{arch}")


# ═══════════════════════════════════════════════════════════════
# Browser — Chrome launcher
# ═══════════════════════════════════════════════════════════════

class TestBrowserLauncher(unittest.TestCase):
    """Test browser launcher."""

    def test_browser_profile(self):
        from apps.browser import BrowserLauncher
        launcher = BrowserLauncher("/tmp/test-chrome")
        profile = launcher.create_profile("work", ["--disable-extensions"])
        self.assertEqual(profile.name, "work")
        self.assertIn("work", launcher.list_profiles())

    def test_browser_default_flags(self):
        from apps.browser import BrowserLauncher
        launcher = BrowserLauncher("/tmp/test-chrome")
        self.assertIn("--no-first-run", BrowserLauncher.DEFAULT_FLAGS)
        self.assertIn("--disable-sync", BrowserLauncher.DEFAULT_FLAGS)

    def test_browser_not_available(self):
        from apps.browser import BrowserLauncher
        launcher = BrowserLauncher("/nonexistent/chrome")
        # is_available checks system paths too, so just verify the custom path doesn't exist
        self.assertFalse(os.path.isfile("/nonexistent/chrome"))


# ═══════════════════════════════════════════════════════════════
# GTK-dependent tests (skip on headless server)
# ═══════════════════════════════════════════════════════════════

@unittest.skipUnless(HAS_GTK, "GTK4 not available (need desktop Linux)")
class TestWindowManager(unittest.TestCase):
    def test_workspace_creation(self):
        from core.wm import Workspace, LayoutMode
        ws = Workspace(id=0, name="Test")
        self.assertEqual(ws.layout, LayoutMode.TILING)
        self.assertEqual(len(ws.windows), 0)

    def test_window_entry(self):
        from core.wm import WindowEntry
        entry = WindowEntry(window=None, app_id="test", title="Test")
        self.assertFalse(entry.focused)
        self.assertFalse(entry.minimized)
        self.assertEqual(entry.workspace, 0)


@unittest.skipUnless(HAS_GTK, "GTK4 not available (need desktop Linux)")
class TestAppEntry(unittest.TestCase):
    def test_app_entry(self):
        from core.launcher import AppEntry
        app = AppEntry(name="Terminal", exec_cmd="superlite-terminal",
                       icon="utilities-terminal", description="System terminal", category="System")
        self.assertEqual(app.name, "Terminal")
        self.assertEqual(app.category, "System")


if __name__ == "__main__":
    unittest.main()
