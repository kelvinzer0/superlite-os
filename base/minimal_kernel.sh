#!/bin/bash
# SuperLite OS — Minimal Kernel Config Generator
# Generates a stripped-down kernel config for flashdisk boot
# Usage: ./minimal_kernel.sh [arch] [output_dir]

set -e

ARCH="${1:-x86_64}"
OUTPUT="${2:-.}"
KERNEL_VER="6.12.87"
CONFIG_FILE="$OUTPUT/.config"

echo "============================================"
echo "  SuperLite Minimal Kernel Config"
echo "  Arch: $ARCH"
echo "  Kernel: $KERNEL_VER"
echo "============================================"
echo ""

# Base: start from tinyconfig
cat > "$CONFIG_FILE" << 'HEADER'
# SuperLite OS — Minimal Kernel Config
# Generated for flashdisk boot — absolute minimum
# Kernel: 6.12.x

HEADER

# Architecture
case "$ARCH" in
    x86_64)
        cat >> "$CONFIG_FILE" << 'EOF'
CONFIG_64BIT=y
CONFIG_X86_64=y
CONFIG_SMP=y
CONFIG_NR_CPUS=4
EOF
        ;;
    aarch64)
        cat >> "$CONFIG_FILE" << 'EOF'
CONFIG_ARM64=y
CONFIG_SMP=y
CONFIG_NR_CPUS=4
EOF
        ;;
    armv7)
        cat >> "$CONFIG_FILE" << 'EOF'
CONFIG_ARM=y
CONFIG_SMP=y
CONFIG_NR_CPUS=4
CONFIG_VFP=y
CONFIG_NEON=y
EOF
        ;;
    riscv64)
        cat >> "$CONFIG_FILE" << 'EOF'
CONFIG_RISCV=y
CONFIG_SMP=y
CONFIG_NR_CPUS=4
CONFIG_64BIT=y
EOF
        ;;
esac

cat >> "$CONFIG_FILE" << 'EOF'

# ─── Compiler Optimization ───
CONFIG_CC_OPTIMIZE_FOR_SIZE=y
CONFIG_BASE_SMALL=y

# ─── No debug ───
CONFIG_PRINTK=n
CONFIG_BUG=n
CONFIG_DEBUG_KERNEL=n
CONFIG_DEBUG_INFO_NONE=y
CONFIG_STACKTRACE=n
CONFIG_PROVE_LOCKING=n
CONFIG_LOCKDEP=n
CONFIG_FTRACE=n
CONFIG_KPROBES=n

# ─── Process ───
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_BINFMT_MISC=n

# ─── Filesystems ───
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=n
CONFIG_EXT4_FS_SECURITY=n
CONFIG_VFAT_FS=y
CONFIG_FAT_DEFAULT_UTF8=y
CONFIG_FAT_DEFAULT_CODEPAGE=437
CONFIG_NTFS3_FS=y
CONFIG_FUSE_FS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y

# ─── Block devices ───
CONFIG_BLK_DEV_SD=y
CONFIG_BLK_DEV_SR=n
CONFIG_BLK_DEV_LOOP=y
CONFIG_BLK_DEV_DM=n

# ─── Storage controllers ───
CONFIG_ATA=y
CONFIG_ATA_PIIX=y
CONFIG_SATA_AHCI=y
CONFIG_NVME_CORE=y
CONFIG_BLK_DEV_NVME=y

# ─── USB ───
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_EHCI_HCD=n
CONFIG_USB_OHCI_HCD=n
CONFIG_USB_STORAGE=y
CONFIG_USB_HID=y
CONFIG_USB_EHCI_HCD=n

# ─── HID (keyboard/mouse) ───
CONFIG_HID=y
CONFIG_HID_GENERIC=y
CONFIG_USB_HID=y
CONFIG_INPUT_EVDEV=y
CONFIG_INPUT_KEYBOARD=y
CONFIG_INPUT_MOUSE=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_MOUSE_PS2=y

# ─── Graphics (framebuffer only — no GPU) ───
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_FB=y
CONFIG_FB_VESA=y
CONFIG_FB_EFI=y
CONFIG_DRM=n
CONFIG_GPU=n

# ─── Network (minimal) ───
CONFIG_NET=y
CONFIG_INET=y
CONFIG_INET_DIAG=n
CONFIG_IPV6=y
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000E=y
CONFIG_NET_VENDOR_REALTEK=y
CONFIG_R8169=y
CONFIG_WLAN=n
CONFIG_BT=n
CONFIG_WIRELESS=n
CONFIG_NETFILTER=n
CONFIG_NF_CONNTRACK=n
CONFIG_BRIDGE=n
CONFIG_VLAN_8021Q=n

# ─── Sound (disabled — save space) ───
CONFIG_SOUND=n
CONFIG_SND=n

# ─── Power Management (minimal) ───
CONFIG_PM=n
CONFIG_HIBERNATION=n
CONFIG_SUSPEND=n
CONFIG_CPU_FREQ=n
CONFIG_CPU_IDLE=n

# ─── Misc disabled ───
CONFIG_SECURITY=n
CONFIG_AUDIT=n
CONFIG_CRYPTO=n
CONFIG_RAID=n
CONFIG_MD=n
CONFIG_LVM=n
CONFIG_FIREWIRE=n
CONFIG_INFINIBAND=n
CONFIG_ISDN=n
CONFIG_PHONE=n
CONFIG_IIO=n
CONFIG_IOMMU=n
CONFIG_VFIO=n
CONFIG_NFS_FS=n
CONFIG_CIFS=n
CONFIG_9P_FS=n
CONFIG_DAX=n
CONFIG_LIBNVDIMM=n
CONFIG_ACPI=n
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_DMI=y
CONFIG_PCCARD=n
CONFIG_PCMCIA=n
CONFIG_PARPORT=n
CONFIG_PPS=n
CONFIG_PTP_1588_CLOCK=n
CONFIG_GPIO=n
CONFIG_EDAC=n
CONFIG_RAS=n
CONFIG_MEMORY_HOTPLUG=n
CONFIG_NUMA=n
EOF

echo "Config written to: $CONFIG_FILE"
echo ""
echo "=== Summary ==="
echo "Total options: $(grep -c "^CONFIG_" "$CONFIG_FILE")"
echo "Enabled (=y):  $(grep -c "=y$" "$CONFIG_FILE")"
echo "Disabled (=n): $(grep -c "=n$" "$CONFIG_FILE")"
echo ""
echo "=== Next steps ==="
echo "1. Copy to kernel source: cp $CONFIG_FILE linux-$KERNEL_VER/.config"
echo "2. Make olddefconfig: cd linux-$KERNEL_VER && make olddefconfig"
echo "3. Compile: make -j\$(nproc) bzImage"
echo "4. Expected size: ~1-2MB bzImage"
echo ""
echo "Or use Alpine kernel directly (pre-built, ~12MB):"
echo "  base/vmlinuz-x86_64"
