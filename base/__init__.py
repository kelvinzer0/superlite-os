"""BusyBox Base - Minimal rootfs builder using BusyBox

Creates a minimal Linux rootfs powered by BusyBox.
This is the foundation layer for SuperLite OS flashdisk builds.
"""

import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class BusyBoxConfig:
    """Configuration for BusyBox rootfs."""
    arch: str = "x86_64"  # x86_64 | i686
    version: str = "1.35.0"
    shell: str = "/bin/sh"
    init_style: str = "busybox"  # busybox | systemd
    hostname: str = "superlite"
    timezone: str = "UTC"
    root_password: str = "root"
    extra_dirs: list[str] = field(default_factory=lambda: [
        "proc", "sys", "dev", "tmp", "run", "mnt", "media", "opt",
    ])
    extra_symlinks: dict = field(default_factory=lambda: {
        # BusyBox multi-call: create symlinks for all applets
        "linuxrc": "bin/busybox",
    })
    # Additional packages to install on top of BusyBox
    extra_packages: list[str] = field(default_factory=list)
    # Network config
    enable_network: bool = True
    enable_dns: bool = True
    dns_servers: list[str] = field(default_factory=lambda: ["8.8.8.8", "1.1.1.1"])


class BusyBoxBase:
    """
    Builds a minimal Linux rootfs using BusyBox.

    BusyBox provides 400+ common UNIX utilities in a single ~1MB binary.
    Perfect for ultra-lightweight flashdisk OS.

    Flow:
    1. Create directory structure
    2. Install BusyBox binary + symlinks
    3. Generate /etc configs
    4. Create init system
    5. Package into initramfs or rootfs
    """

    # Supported architectures — BusyBox 1.37.0 static (Alpine Linux)
    SUPPORTED_ARCHES = {
        "x86_64":  {"elf": "ELF 64-bit LSB executable, x86-64",    "endian": "little", "bits": 64, "qemu": "qemu-x86_64"},
        "i686":    {"elf": "ELF 32-bit LSB executable, Intel 80386","endian": "little", "bits": 32, "qemu": "qemu-i386"},
        "aarch64": {"elf": "ELF 64-bit LSB executable, ARM aarch64","endian": "little", "bits": 64, "qemu": "qemu-aarch64"},
        "armv7":   {"elf": "ELF 32-bit LSB executable, ARM",        "endian": "little", "bits": 32, "qemu": "qemu-arm"},
        "armhf":   {"elf": "ELF 32-bit LSB executable, ARM",        "endian": "little", "bits": 32, "qemu": "qemu-arm"},
        "ppc64le": {"elf": "ELF 64-bit LSB executable, 64-bit PowerPC","endian": "little","bits": 64,"qemu": "qemu-ppc64le"},
        "s390x":   {"elf": "ELF 64-bit MSB executable, IBM S/390",  "endian": "big",    "bits": 64, "qemu": "qemu-s390x"},
        "riscv64": {"elf": "ELF 64-bit LSB executable, UCB RISC-V", "endian": "little", "bits": 64, "qemu": "qemu-riscv64"},
    }

    # Auto-detect host architecture
    @staticmethod
    def detect_arch() -> str:
        import platform
        machine = platform.machine().lower()
        arch_map = {
            "x86_64": "x86_64", "amd64": "x86_64",
            "i686": "i686", "i386": "i686", "i586": "i686",
            "aarch64": "aarch64", "arm64": "aarch64",
            "armv7l": "armv7", "armv7": "armv7",
            "armv6l": "armhf", "armhf": "armhf",
            "ppc64le": "ppc64le",
            "s390x": "s390x",
            "riscv64": "riscv64",
        }
        return arch_map.get(machine, "x86_64")

    # Essential BusyBox applets for a working system
    ESSENTIAL_APPLETS = [
        # Shell & core
        "sh", "ash", "bash", "busybox",
        # File operations
        "cat", "cp", "mv", "rm", "ls", "ln", "mkdir", "rmdir", "chmod", "chown",
        "chgrp", "touch", "find", "grep", "sed", "awk", "cut", "sort", "uniq",
        "wc", "head", "tail", "more", "less", "vi",
        # System
        "mount", "umount", "df", "du", "free", "ps", "kill", "killall",
        "pidof", "sync", "reboot", "poweroff", "halt",
        # Users
        "adduser", "addgroup", "deluser", "delgroup", "su", "login",
        "passwd", "whoami", "id", "who",
        # Network
        "ifconfig", "route", "ping", "wget", "nc", "telnet", "nslookup",
        "hostname", "ip",
        # Archive
        "tar", "gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz",
        "cpio", "gzip",
        # Dev
        "mknod", "mkfifo", "ln", "readlink", "realpath",
        # Misc
        "date", "cal", "echo", "printf", "test", "true", "false",
        "sleep", "yes", "seq", "expr", "basename", "dirname",
        "uname", "uptime", "dmesg", "syslogd", "klogd",
        # Init
        "init", "switch_root", "poweroff", "reboot", "halt",
    ]

    def __init__(self, config: BusyBoxConfig = None, work_dir: str = None):
        self.config = config or BusyBoxConfig()
        self.work_dir = work_dir or tempfile.mkdtemp(prefix="superlite-busybox-")
        self.rootfs = os.path.join(self.work_dir, "rootfs")
        self.busybox_path: Optional[str] = None

    def build(self, output: str = None) -> str:
        """
        Build complete BusyBox rootfs.
        Returns path to rootfs directory.
        """
        print(f"[BusyBox] Building {self.config.arch} rootfs...")

        self._create_structure()
        self._install_busybox()
        self._create_symlinks()
        self._generate_etc()
        self._create_init()
        self._setup_network()
        self._create_dev_nodes()

        if output:
            if os.path.isdir(output):
                shutil.rmtree(output)
            shutil.copytree(self.rootfs, output)
            print(f"[BusyBox] Rootfs installed to: {output}")
            return output

        print(f"[BusyBox] Rootfs ready at: {self.rootfs}")
        return self.rootfs

    def build_initramfs(self, output: str = None) -> str:
        """
        Build a bootable initramfs (cpio.gz) from BusyBox rootfs.
        """
        print("[BusyBox] Building initramfs...")

        # Build rootfs first
        self.build()

        # Create initramfs-specific init
        self._create_initramfs_init()

        # Pack into cpio
        output = output or os.path.join(self.work_dir, "initramfs.cpio.gz")

        cmd = f"cd {self.rootfs} && find . | cpio -o -H newc 2>/dev/null | gzip > {output}"
        subprocess.run(cmd, shell=True, check=True, timeout=60)

        size = os.path.getsize(output)
        print(f"[BusyBox] Initramfs: {output} ({size / 1024:.0f}KB)")
        return output

    def _create_structure(self):
        """Create minimal directory structure."""
        dirs = [
            "bin", "sbin", "usr/bin", "usr/sbin", "usr/lib",
            "lib", "lib64", "etc", "etc/init.d", "etc/network",
            "root", "home", "var", "var/log", "var/run", "var/tmp",
            "tmp", "proc", "sys", "dev", "dev/pts", "dev/shm",
            "run", "mnt", "media", "opt",
        ]
        for d in dirs:
            os.makedirs(os.path.join(self.rootfs, d), exist_ok=True)

    def _install_busybox(self):
        """Install BusyBox binary."""
        bb_src = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            f"busybox-{self.config.arch}"
        )

        if not os.path.isfile(bb_src):
            raise FileNotFoundError(
                f"BusyBox binary not found: {bb_src}\n"
                f"Supported architectures: {', '.join(self.SUPPORTED_ARCHES.keys())}"
            )

        # Install to rootfs
        dest = os.path.join(self.rootfs, "bin/busybox")
        shutil.copy2(bb_src, dest)
        os.chmod(dest, 0o755)
        self.busybox_path = dest

        # Verify (may fail for foreign arch without QEMU)
        try:
            result = subprocess.run(
                [dest, "--help"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                version_line = result.stdout.split("\n")[0]
                print(f"[BusyBox] Installed: {version_line}")
            else:
                size = os.path.getsize(dest)
                print(f"[BusyBox] Installed: {self.config.arch} ({size // 1024}KB) — native exec not available")
        except (OSError, subprocess.TimeoutExpired):
            size = os.path.getsize(dest)
            print(f"[BusyBox] Installed: {self.config.arch} ({size // 1024}KB) — cross-arch binary")

    def _create_symlinks(self):
        """Create symlinks for all BusyBox applets."""
        bb = os.path.join(self.rootfs, "bin/busybox")

        # Get list of applets
        result = subprocess.run(
            [bb, "--list"],
            capture_output=True, text=True, timeout=5
        )
        applets = result.stdout.strip().split("\n")

        created = 0
        for applet in applets:
            applet = applet.strip()
            if not applet:
                continue

            # Link in /bin
            link = os.path.join(self.rootfs, "bin", applet)
            if not os.path.exists(link):
                os.symlink("busybox", link)
                created += 1

            # Some applets belong in /sbin
            sbin_applets = [
                "init", "reboot", "poweroff", "halt", "shutdown",
                "ifconfig", "route", "ip", "iptables", "modprobe",
                "depmod", "mdev", "udevd", "syslogd", "klogd",
                "mkswap", "swapon", "swapoff", "fdisk", "mkfs.ext4",
                "mkfs.vfat", "fsck", "mount", "umount",
            ]
            if applet in sbin_applets:
                sbin_link = os.path.join(self.rootfs, "sbin", applet)
                if not os.path.exists(sbin_link):
                    os.symlink("../bin/busybox", sbin_link)

        # Extra symlinks
        for src, dst in self.config.extra_symlinks.items():
            link = os.path.join(self.rootfs, src)
            if not os.path.exists(link):
                os.symlink(dst, link)

        print(f"[BusyBox] Created {created} applet symlinks")

    def _generate_etc(self):
        """Generate /etc configuration files."""
        rootfs = self.rootfs

        # /etc/passwd
        with open(os.path.join(rootfs, "etc/passwd"), "w") as f:
            f.write("root:x:0:0:root:/root:/bin/sh\n")
            f.write("daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\n")
            f.write("nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin\n")

        # /etc/group
        with open(os.path.join(rootfs, "etc/group"), "w") as f:
            f.write("root:x:0:\n")
            f.write("daemon:x:1:\n")
            f.write("tty:x:5:\n")
            f.write("disk:x:6:\n")
            f.write("audio:x:29:\n")
            f.write("video:x:44:\n")
            f.write("staff:x:50:\n")
            f.write("users:x:100:\n")

        # /etc/shadow
        with open(os.path.join(rootfs, "etc/shadow"), "w") as f:
            f.write(f"root:{self.config.root_password}:19000:0:99999:7:::\n")
            f.write("daemon:*:19000:0:99999:7:::\n")
            f.write("nobody:*:19000:0:99999:7:::\n")
        os.chmod(os.path.join(rootfs, "etc/shadow"), 0o600)

        # /etc/hostname
        with open(os.path.join(rootfs, "etc/hostname"), "w") as f:
            f.write(self.config.hostname + "\n")

        # /etc/hosts
        with open(os.path.join(rootfs, "etc/hosts"), "w") as f:
            f.write("127.0.0.1\tlocalhost\n")
            f.write(f"127.0.1.1\t{self.config.hostname}\n")
            f.write("::1\t\tlocalhost ip6-localhost ip6-loopback\n")

        # /etc/fstab
        with open(os.path.join(rootfs, "etc/fstab"), "w") as f:
            f.write("# <device>\t<mount>\t<type>\t<options>\t<dump>\t<pass>\n")
            f.write("proc\t\t/proc\tproc\tdefaults\t0\t0\n")
            f.write("sysfs\t\t/sys\tsysfs\tdefaults\t0\t0\n")
            f.write("devtmpfs\t/dev\tdevtmpfs\tdefaults\t0\t0\n")
            f.write("tmpfs\t\t/tmp\ttmpfs\tdefaults,noatime\t0\t0\n")
            f.write("tmpfs\t\t/run\ttmpfs\tdefaults,noatime\t0\t0\n")

        # /etc/inittab (BusyBox init)
        with open(os.path.join(rootfs, "etc/inittab"), "w") as f:
            f.write("# SuperLite OS - BusyBox init\n\n")
            f.write("# System initialization\n")
            f.write("::sysinit:/etc/init.d/rcS\n\n")
            f.write("# Shell on console\n")
            f.write("::respawn:-/bin/sh\n\n")
            f.write("# Ctrl+Alt+Del\n")
            f.write("::ctrlaltdel:/sbin/reboot\n\n")
            f.write("# Shutdown/restart\n")
            f.write("::shutdown:/bin/umount -a -r\n")
            f.write("::restart:/sbin/init\n")

        # /etc/init.d/rcS (startup script)
        rcS = os.path.join(rootfs, "etc/init.d/rcS")
        with open(rcS, "w") as f:
            f.write("#!/bin/sh\n\n")
            f.write("echo 'SuperLite OS starting...'\n\n")
            f.write("# Mount virtual filesystems\n")
            f.write("mount -t proc proc /proc\n")
            f.write("mount -t sysfs sysfs /sys\n")
            f.write("mount -t devtmpfs devtmpfs /dev\n")
            f.write("mkdir -p /dev/pts /dev/shm\n")
            f.write("mount -t devpts devpts /dev/pts\n")
            f.write("mount -t tmpfs tmpfs /dev/shm\n")
            f.write("mount -t tmpfs tmpfs /run\n\n")
            f.write("# Set hostname\n")
            f.write(f"hostname {self.config.hostname}\n\n")
            f.write("# Setup network\n")
            f.write("ifconfig lo 127.0.0.1 up\n")
            f.write("if [ -f /etc/network/interfaces ]; then\n")
            f.write("    . /etc/network/interfaces\n")
            f.write("fi\n\n")
            f.write("# Start syslog\n")
            f.write("syslogd -O /var/log/messages\n")
            f.write("klogd\n\n")
            f.write("# Set timezone\n")
            f.write(f"export TZ={self.config.timezone}\n\n")
            f.write("echo 'SuperLite OS ready.'\n")
        os.chmod(rcS, 0o755)

        # /etc/profile
        with open(os.path.join(rootfs, "etc/profile"), "w") as f:
            f.write("export PATH=/bin:/sbin:/usr/bin:/usr/sbin\n")
            f.write("export HOME=/root\n")
            f.write("export TERM=linux\n")
            f.write("export PS1='\\[\\033[1;31m\\]SuperLite\\[\\033[0m\\]:\\w\\$ '\n")
            f.write("alias ls='ls --color=auto'\n")
            f.write("alias ll='ls -la'\n")
            f.write("alias la='ls -a'\n")

        # /etc/resolv.conf
        if self.config.enable_dns:
            with open(os.path.join(rootfs, "etc/resolv.conf"), "w") as f:
                for dns in self.config.dns_servers:
                    f.write(f"nameserver {dns}\n")

        # /etc/nsswitch.conf
        with open(os.path.join(rootfs, "etc/nsswitch.conf"), "w") as f:
            f.write("hosts: files dns\n")
            f.write("passwd: files\n")
            f.write("group: files\n")

        # /etc/motd
        with open(os.path.join(rootfs, "etc/motd"), "w") as f:
            f.write("\n")
            f.write("  ╔══════════════════════════════════╗\n")
            f.write("  ║     ⚡ SuperLite OS v0.1.0       ║\n")
            f.write("  ║   Ultra-lightweight Linux DE     ║\n")
            f.write("  ╚══════════════════════════════════╝\n")
            f.write("\n")
            f.write("  Type 'busybox --list' for available commands\n")
            f.write("\n")

        # /etc/issue
        with open(os.path.join(rootfs, "etc/issue"), "w") as f:
            f.write("SuperLite OS \\r (\\l)\n\n")

        print("[BusyBox] Generated /etc configuration")

    def _create_init(self):
        """Create /sbin/init for BusyBox init system."""
        init_path = os.path.join(self.rootfs, "sbin/init")
        # BusyBox init is already symlinked, but we can create a wrapper
        # if custom init is needed
        pass

    def _create_initramfs_init(self):
        """Create specialized init for initramfs booting."""
        init_path = os.path.join(self.rootfs, "init")
        with open(init_path, "w") as f:
            f.write("#!/bin/sh\n\n")
            f.write("# SuperLite OS - initramfs init\n\n")
            f.write("# Mount virtual filesystems\n")
            f.write("mount -t proc proc /proc\n")
            f.write("mount -t sysfs sysfs /sys\n")
            f.write("mount -t devtmpfs devtmpfs /dev\n\n")
            f.write("# Wait for devices\n")
            f.write("echo 'Waiting for devices...'\n")
            f.write("sleep 1\n\n")
            f.write("# Try to find and mount root\n")
            f.write("echo 'Searching for root filesystem...'\n\n")
            f.write("# Try common root locations\n")
            f.write("for dev in /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/nvme0n1p1; do\n")
            f.write("    if [ -b \"$dev\" ]; then\n")
            f.write("        echo \"Trying $dev...\"\n")
            f.write("        mount -t ext4 \"$dev\" /mnt 2>/dev/null && \\\n")
            f.write("            echo \"Root found on $dev\" && \\\n")
            f.write("            exec switch_root /mnt /sbin/init\n")
            f.write("    fi\n")
            f.write("done\n\n")
            f.write("# Fallback: drop to shell\n")
            f.write("echo 'Could not find root filesystem.'\n")
            f.write("echo 'Dropping to rescue shell.'\n")
            f.write("exec /bin/sh\n")
        os.chmod(init_path, 0o755)

    def _setup_network(self):
        """Setup basic network configuration."""
        if not self.config.enable_network:
            return

        # /etc/network/interfaces
        iface_dir = os.path.join(self.rootfs, "etc/network")
        os.makedirs(iface_dir, exist_ok=True)

        with open(os.path.join(iface_dir, "interfaces"), "w") as f:
            f.write("# Loopback\n")
            f.write("ifconfig lo 127.0.0.1 up\n\n")
            f.write("# DHCP on first ethernet interface\n")
            f.write("# Uncomment and modify as needed:\n")
            f.write("# ifconfig eth0 up\n")
            f.write("# udhcpc -i eth0\n")

        # udhcpc script (BusyBox DHCP client)
        udhcpc_dir = os.path.join(self.rootfs, "usr/share/udhcpc")
        os.makedirs(udhcpc_dir, exist_ok=True)

        with open(os.path.join(udhcpc_dir, "default.script"), "w") as f:
            f.write("#!/bin/sh\n\n")
            f.write("case \"$1\" in\n")
            f.write("    deconfig)\n")
            f.write("        ifconfig $interface 0.0.0.0\n")
            f.write("        ;;\n")
            f.write("    renew|bound)\n")
            f.write("        ifconfig $interface $ip $BROADCAST $netmask\n")
            f.write("        if [ -n \"$router\" ]; then\n")
            f.write("            route del default 2>/dev/null\n")
            f.write("            route add default gw $router\n")
            f.write("        fi\n")
            f.write("        if [ -n \"$dns\" ]; then\n")
            f.write("            echo -n > /etc/resolv.conf\n")
            f.write("            for i in $dns; do\n")
            f.write("                echo \"nameserver $i\" >> /etc/resolv.conf\n")
            f.write("            done\n")
            f.write("        fi\n")
            f.write("        ;;\n")
            f.write("esac\n")
        os.chmod(os.path.join(udhcpc_dir, "default.script"), 0o755)

        print("[BusyBox] Network configured")

    def _create_dev_nodes(self):
        """Create essential device nodes."""
        dev = os.path.join(self.rootfs, "dev")
        nodes = [
            ("null", "c", 1, 3),
            ("zero", "c", 1, 5),
            ("random", "c", 1, 8),
            ("urandom", "c", 1, 9),
            ("tty", "c", 5, 0),
            ("console", "c", 5, 1),
            ("ptmx", "c", 5, 2),
            ("tty0", "c", 4, 0),
            ("tty1", "c", 4, 1),
            ("tty2", "c", 4, 2),
            ("tty3", "c", 4, 3),
            ("tty4", "c", 4, 4),
        ]
        for name, typ, major, minor in nodes:
            path = os.path.join(dev, name)
            if not os.path.exists(path):
                try:
                    subprocess.run(
                        ["mknod", path, typ, str(major), str(minor)],
                        capture_output=True, timeout=5
                    )
                    os.chmod(path, 0o666)
                except Exception:
                    # mknod may fail without root, create placeholder
                    with open(path, "w") as f:
                        f.write(f"# device node: {typ} {major}:{minor}\n")

        print("[BusyBox] Device nodes created")

    def get_applet_list(self) -> list[str]:
        """Get list of available BusyBox applets."""
        bb = os.path.join(self.rootfs, "bin/busybox")
        if not os.path.isfile(bb):
            return []
        result = subprocess.run(
            [bb, "--list"],
            capture_output=True, text=True, timeout=5
        )
        return sorted(result.stdout.strip().split("\n"))

    def get_size(self) -> int:
        """Get total rootfs size in bytes."""
        total = 0
        for root, dirs, files in os.walk(self.rootfs):
            for f in files:
                path = os.path.join(root, f)
                if not os.path.islink(path):
                    total += os.path.getsize(path)
        return total


def create_superlite_base(arch: str = None, output: str = None) -> str:
    """Convenience function to create SuperLite BusyBox base.

    Args:
        arch: Target architecture. Auto-detects host arch if None.
              Supported: x86_64, i686, aarch64, armv7, armhf, ppc64le, s390x, riscv64
        output: Output directory. Defaults to ~/.superlite/rootfs
    """
    arch = arch or BusyBoxConfig.detect_arch()
    if arch not in BusyBoxBase.SUPPORTED_ARCHES:
        raise ValueError(f"Unsupported arch '{arch}'. Supported: {', '.join(BusyBoxBase.SUPPORTED_ARCHES.keys())}")

    config = BusyBoxConfig(
        arch=arch,
        hostname="superlite",
        enable_network=True,
    )
    builder = BusyBoxBase(config)
    return builder.build(output or os.path.expanduser("~/.superlite/rootfs"))
