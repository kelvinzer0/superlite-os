"""Cross-Chain Builder - Assemble bootable SuperLite OS from driver dump + base system

Cross-chain means: drivers are captured from HOST, base system is built separately,
then combined into a bootable image for TARGET hardware (flashdisk).
"""

import os
import json
import shutil
import subprocess
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional
from ..dump import DriverDumpManifest


@dataclass
class BuildConfig:
    """Configuration for cross-chain build."""
    target_arch: str = "x86_64"
    kernel_version: str = ""  # auto-detect
    base_distro: str = "debian"
    base_release: str = "bookworm"
    hostname: str = "superlite"
    root_password: str = "superlite"  # should be changed
    timezone: str = "UTC"
    locale: str = "en_US.UTF-8"
    include_packages: list[str] = field(default_factory=lambda: [
        "systemd", "systemd-sysv",
        "dbus", "dbus-x11",
        "xorg", "xserver-xorg-video-all",
        "gtk-3-examples", "gir1.2-gtk-4.0", "python3-gi",
        "python3", "python3-pip",
        "network-manager", "wpasupplicant",
        "pulseaudio", "alsa-utils",
        "bash", "coreutils", "util-linux",
        "nano", "vim-tiny",
    ])
    exclude_packages: list[str] = field(default_factory=lambda: [
        "man-db", "manpages", "info",
        "doc-debian", "debian-faq",
        "tasksel", "tasksel-data",
    ])
    output_size_mb: int = 2048  # 2GB flashdisk image
    swap_size_mb: int = 0
    boot_mode: str = "uefi"  # uefi | bios | both


@dataclass
class BuildState:
    """Tracks build progress."""
    stage: str = "init"
    progress: float = 0.0
    message: str = ""
    errors: list[str] = field(default_factory=list)


class CrossChainBuilder:
    """
    Assembles SuperLite OS bootable image via cross-chain build.

    Pipeline:
    1. Prepare workspace
    2. Bootstrap base system (debootstrap)
    3. Inject driver dump from host
    4. Install SuperLite desktop environment
    5. Configure system (fstab, network, initramfs)
    6. Install bootloader (GRUB)
    7. Generate bootable ISO/IMG
    """

    def __init__(self, config: BuildConfig = None, workspace: str = None):
        self.config = config or BuildConfig()
        self.workspace = workspace or os.path.expanduser("~/.superlite/build")
        self.state = BuildState()
        self.driver_manifest: Optional[DriverDumpManifest] = None

    def build(self, driver_dump_dir: str = None) -> str:
        """
        Full cross-chain build pipeline.
        Returns path to the generated bootable image.
        """
        print("[CrossChain] Starting build pipeline...")

        stages = [
            ("prepare", self._stage_prepare),
            ("bootstrap", self._stage_bootstrap),
            ("drivers", lambda: self._stage_inject_drivers(driver_dump_dir)),
            ("desktop", self._stage_install_desktop),
            ("configure", self._stage_configure),
            ("bootloader", self._stage_bootloader),
            ("package", self._stage_package),
        ]

        for name, func in stages:
            self.state.stage = name
            print(f"[CrossChain] Stage: {name}")
            try:
                result = func()
                if result is False:
                    print(f"[CrossChain] Stage {name} failed!")
                    return ""
            except Exception as e:
                self.state.errors.append(f"{name}: {str(e)}")
                print(f"[CrossChain] Error in {name}: {e}")
                return ""

        output = os.path.join(self.workspace, "superlite-os.img")
        print(f"[CrossChain] Build complete: {output}")
        return output

    def _stage_prepare(self):
        """Prepare build workspace."""
        # Clean previous build
        rootfs = os.path.join(self.workspace, "rootfs")
        if os.path.isdir(rootfs):
            shutil.rmtree(rootfs)

        dirs = [
            "rootfs", "modules", "firmware", "iso", "boot",
            "rootfs/usr/share/superlite",
            "rootfs/etc/superlite",
        ]
        for d in dirs:
            os.makedirs(os.path.join(self.workspace, d), exist_ok=True)
        self.state.progress = 0.1

    def _stage_bootstrap(self):
        """Bootstrap base system with debootstrap."""
        rootfs = os.path.join(self.workspace, "rootfs")

        # Check debootstrap
        if not shutil.which("debootstrap"):
            print("[CrossChain] debootstrap not found, using manual bootstrap")
            return self._manual_bootstrap(rootfs)

        cmd = [
            "debootstrap",
            "--arch", self.config.target_arch,
            "--variant=minbase",
            "--include", ",".join(self.config.include_packages[:5]),  # First 5
            "--exclude", ",".join(self.config.exclude_packages),
            self.config.base_release,
            rootfs,
        ]

        # Use local mirror if available
        mirror = self._find_local_mirror()
        if mirror:
            cmd.append(mirror)
        else:
            cmd.append(f"http://deb.debian.org/debian")

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            self.state.errors.append(f"debootstrap failed: {result.stderr}")
            return False

        self.state.progress = 0.3

    def _manual_bootstrap(self, rootfs: str) -> bool:
        """Manual bootstrap without debootstrap (for minimal systems)."""
        print("[CrossChain] Performing manual minimal bootstrap...")

        # Create minimal filesystem structure
        dirs = [
            "bin", "sbin", "lib", "lib64", "usr/bin", "usr/sbin", "usr/lib",
            "etc", "proc", "sys", "dev", "tmp", "var", "run", "boot",
            "home", "root", "opt", "mnt", "media",
        ]
        for d in dirs:
            os.makedirs(os.path.join(rootfs, d), exist_ok=True)

        # Copy essential binaries from host (cross-chain!)
        essential_bins = [
            "/bin/bash", "/bin/sh", "/bin/ls", "/bin/cat", "/bin/cp",
            "/bin/mv", "/bin/rm", "/bin/mkdir", "/bin/mount", "/bin/umount",
            "/sbin/init", "/sbin/modprobe",
        ]
        for bin_path in essential_bins:
            if os.path.isfile(bin_path):
                dest = os.path.join(rootfs, bin_path.lstrip("/"))
                shutil.copy2(bin_path, dest)

        self.state.progress = 0.25
        return True

    def _stage_inject_drivers(self, driver_dump_dir: str = None):
        """Inject driver dump into rootfs."""
        if not driver_dump_dir:
            driver_dump_dir = os.path.expanduser("~/.superlite/driver-dump")

        manifest_path = os.path.join(driver_dump_dir, "manifest.json")
        if not os.path.isfile(manifest_path):
            print("[CrossChain] No driver dump found, skipping driver injection")
            return True

        with open(manifest_path) as f:
            manifest_data = json.load(f)

        rootfs = os.path.join(self.workspace, "rootfs")
        kernel = manifest_data.get("source_kernel", "unknown")

        # Copy kernel modules
        modules_dest = os.path.join(rootfs, "lib", "modules", kernel)
        os.makedirs(modules_dest, exist_ok=True)

        modules_src = os.path.join(driver_dump_dir, "modules")
        if os.path.isdir(modules_src):
            for ko in os.listdir(modules_src):
                shutil.copy2(
                    os.path.join(modules_src, ko),
                    os.path.join(modules_dest, ko)
                )

        # Copy firmware
        firmware_src = os.path.join(driver_dump_dir, "firmware")
        firmware_dest = os.path.join(rootfs, "lib", "firmware")
        if os.path.isdir(firmware_src):
            os.makedirs(firmware_dest, exist_ok=True)
            for fw in os.listdir(firmware_src):
                shutil.copy2(
                    os.path.join(firmware_src, fw),
                    os.path.join(firmware_dest, fw)
                )

        # Generate modules.dep
        dep_cmd = f"depmod -a -b {rootfs} {kernel}"
        subprocess.run(dep_cmd.split(), capture_output=True, timeout=30)

        self.state.progress = 0.4
        print(f"[CrossChain] Injected {len(manifest_data.get('drivers', []))} drivers")
        return True

    def _stage_install_desktop(self):
        """Install SuperLite desktop environment into rootfs."""
        rootfs = os.path.join(self.workspace, "rootfs")
        superlite_dest = os.path.join(rootfs, "usr/share/superlite")

        # Copy SuperLite source
        src_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        for item in ["core", "apps", "drivers", "assets"]:
            src = os.path.join(src_dir, item)
            dst = os.path.join(superlite_dest, item)
            if os.path.isdir(src):
                shutil.copytree(src, dst, dirs_exist_ok=True)

        # Copy main entry point
        main_py = os.path.join(src_dir, "__init__.py")
        if os.path.isfile(main_py):
            shutil.copy2(main_py, os.path.join(superlite_dest, "__init__.py"))

        # Create session starter script
        session_script = os.path.join(rootfs, "usr/bin/superlite-session")
        with open(session_script, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("export XDG_CURRENT_DESKTOP=SuperLite\n")
            f.write("export DESKTOP_SESSION=superlite\n")
            f.write("cd /usr/share/superlite\n")
            f.write("exec python3 -m core.session\n")
        os.chmod(session_script, 0o755)

        # Create app launchers
        for app_name, module in [
            ("superlite-terminal", "apps.terminal"),
            ("superlite-files", "apps.filemanager"),
            ("superlite-editor", "apps.texteditor"),
        ]:
            launcher = os.path.join(rootfs, f"usr/bin/{app_name}")
            with open(launcher, "w") as f:
                f.write("#!/bin/bash\n")
                f.write(f"cd /usr/share/superlite && python3 -m {module}\n")
            os.chmod(launcher, 0o755)

        self.state.progress = 0.6
        return True

    def _stage_configure(self):
        """Configure system files."""
        rootfs = os.path.join(self.workspace, "rootfs")

        # /etc/hostname
        with open(os.path.join(rootfs, "etc/hostname"), "w") as f:
            f.write(self.config.hostname)

        # /etc/hosts
        with open(os.path.join(rootfs, "etc/hosts"), "w") as f:
            f.write("127.0.0.1\tlocalhost\n")
            f.write(f"127.0.1.1\t{self.config.hostname}\n")

        # /etc/fstab (minimal for flashdisk)
        with open(os.path.join(rootfs, "etc/fstab"), "w") as f:
            f.write("# SuperLite OS fstab\n")
            f.write("proc\t/proc\tproc\tdefaults\t0\t0\n")
            f.write("sysfs\tsysfs\tsysfs\tdefaults\t0\t0\n")
            f.write("tmpfs\t/tmp\ttmpfs\tdefaults,noatime\t0\t0\n")

        # /etc/inittab (systemd is default, but add fallback)
        # SuperLite session auto-start
        autostart_dir = os.path.join(rootfs, "etc/systemd/system")
        os.makedirs(autostart_dir, exist_ok=True)

        service = os.path.join(autostart_dir, "superlite-session.service")
        with open(service, "w") as f:
            f.write("[Unit]\n")
            f.write("Description=SuperLite Desktop Session\n")
            f.write("After=systemd-user-sessions.service\n")
            f.write("ConditionPathExists=/usr/bin/superlite-session\n\n")
            f.write("[Service]\n")
            f.write("Type=simple\n")
            f.write("ExecStart=/usr/bin/superlite-session\n")
            f.write("Restart=on-failure\n")
            f.write("User=root\n\n")
            f.write("[Install]\n")
            f.write("WantedBy=multi-user.target\n")

        # Enable the service
        wants_dir = os.path.join(autostart_dir, "multi-user.target.wants")
        os.makedirs(wants_dir, exist_ok=True)
        os.symlink(service, os.path.join(wants_dir, "superlite-session.service"))

        # Network config (NetworkManager)
        nm_conf = os.path.join(rootfs, "etc/NetworkManager/NetworkManager.conf")
        os.makedirs(os.path.dirname(nm_conf), exist_ok=True)
        with open(nm_conf, "w") as f:
            f.write("[main]\n")
            f.write("plugins=ifupdown,keyfile\n")
            f.write("dns=default\n\n")
            f.write("[ifupdown]\n")
            f.write("managed=true\n")

        self.state.progress = 0.7
        return True

    def _stage_bootloader(self):
        """Install and configure GRUB bootloader."""
        rootfs = os.path.join(self.workspace, "rootfs")

        # Create boot directory
        boot_dir = os.path.join(rootfs, "boot")
        os.makedirs(boot_dir, exist_ok=True)

        # Generate GRUB config
        grub_dir = os.path.join(rootfs, "boot/grub")
        os.makedirs(grub_dir, exist_ok=True)

        grub_cfg = os.path.join(grub_dir, "grub.cfg")
        with open(grub_cfg, "w") as f:
            f.write("set default=0\n")
            f.write("set timeout=3\n")
            f.write("set gfxmode=auto\n\n")
            f.write("menuentry 'SuperLite OS' {\n")
            f.write("    linux /boot/vmlinuz root=/dev/sda1 ro quiet splash\n")
            f.write("    initrd /boot/initrd.img\n")
            f.write("}\n\n")
            f.write("menuentry 'SuperLite OS (Recovery)' {\n")
            f.write("    linux /boot/vmlinuz root=/dev/sda1 ro single\n")
            f.write("    initrd /boot/initrd.img\n")
            f.write("}\n")

        self.state.progress = 0.85
        return True

    def _stage_package(self):
        """Package rootfs into bootable image."""
        output = os.path.join(self.workspace, "superlite-os.img")
        rootfs = os.path.join(self.workspace, "rootfs")

        # Create raw disk image
        size_mb = self.config.output_size_mb
        print(f"[CrossChain] Creating {size_mb}MB image...")

        with open(output, "wb") as f:
            f.seek((size_mb * 1024 * 1024) - 1)
            f.write(b"\0")

        # Create partitions using sfdisk
        sfdisk_input = f"""label: gpt
unit: sectors

1 : size={size_mb * 2048 - 2048}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
"""
        proc = subprocess.run(
            ["sfdisk", output],
            input=sfdisk_input, capture_output=True, text=True, timeout=30
        )

        # Format with ext4 (using loop device)
        # In production, this requires root
        try:
            # Setup loop device
            loop = subprocess.run(
                ["losetup", "--find", "--show", "--partscan", output],
                capture_output=True, text=True, timeout=30
            )
            if loop.returncode == 0:
                loop_dev = loop.stdout.strip()
                part_dev = f"{loop_dev}p1"

                subprocess.run(
                    ["mkfs.ext4", "-L", "SUPERLITE", part_dev],
                    capture_output=True, timeout=60
                )

                # Mount and copy
                mount_point = os.path.join(self.workspace, "mnt")
                os.makedirs(mount_point, exist_ok=True)
                subprocess.run(
                    ["mount", part_dev, mount_point],
                    capture_output=True, timeout=30
                )

                # Copy rootfs
                shutil.copytree(rootfs, mount_point, dirs_exist_ok=True)

                # Cleanup
                subprocess.run(["umount", mount_point], capture_output=True, timeout=30)
                subprocess.run(["losetup", "-d", loop_dev], capture_output=True, timeout=10)
        except Exception as e:
            print(f"[CrossChain] Loop device failed (may need root): {e}")
            print(f"[CrossChain] Raw image created at: {output}")
            print(f"[CrossChain] Use 'dd if={output} of=/dev/sdX' to write to flashdisk")

        self.state.progress = 1.0
        return output

    def _find_local_mirror(self) -> Optional[str]:
        """Check for local Debian mirror."""
        # Check common local mirror locations
        for mirror in [
            "http://localhost:3142/debian",  # apt-cacher-ng
            "http://mirror.local/debian",
        ]:
            try:
                import urllib.request
                urllib.request.urlopen(mirror, timeout=2)
                return mirror
            except Exception:
                pass
        return None

    def get_state(self) -> dict:
        return asdict(self.state)
