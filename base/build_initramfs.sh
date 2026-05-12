#!/bin/sh
# SuperLite OS - Multi-architecture initramfs builder
# Usage: ./build_initramfs.sh [arch]
# Supported: x86_64 i686 aarch64 armv7 armhf ppc64le s390x riscv64
# Output: initramfs-<arch>.cpio.gz

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="${1:-$(uname -m)}"

# Normalize architecture name
case "$ARCH" in
    x86_64|amd64)         ARCH="x86_64" ;;
    i686|i386|i586)       ARCH="i686" ;;
    aarch64|arm64)        ARCH="aarch64" ;;
    armv7l|armv7)         ARCH="armv7" ;;
    armv6l|armhf)         ARCH="armhf" ;;
    ppc64le)              ARCH="ppc64le" ;;
    s390x)                ARCH="s390x" ;;
    riscv64)              ARCH="riscv64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        echo "Supported: x86_64 i686 aarch64 armv7 armhf ppc64le s390x riscv64"
        exit 1
        ;;
esac

BB="$SCRIPT_DIR/busybox-$ARCH"
if [ ! -f "$BB" ]; then
    echo "Error: BusyBox binary not found: $BB"
    echo "Expected: busybox-$ARCH"
    exit 1
fi

WORKDIR="$(mktemp -d /tmp/superlite-${ARCH}-XXXXXX)"
ROOTFS="$WORKDIR/rootfs"
OUTPUT="$SCRIPT_DIR/initramfs-${ARCH}.cpio.gz"

echo "============================================"
echo "  SuperLite OS Initramfs Builder"
echo "  Arch: $ARCH"
echo "  BusyBox: $BB"
echo "  Output: $OUTPUT"
echo "============================================"
echo ""

# Create rootfs structure
mkdir -p "$ROOTFS"/{bin,sbin,usr/bin,usr/sbin,etc,proc,sys,dev,tmp,root,mnt,lib,lib64}

# Install BusyBox
cp "$BB" "$ROOTFS/bin/busybox"
chmod +x "$ROOTFS/bin/busybox"

# Use host busybox to list applets (cross-arch can't exec foreign binary)
HOST_BB="$SCRIPT_DIR/busybox-$(uname -m)"
if [ ! -f "$HOST_BB" ]; then
    HOST_BB="$BB"
fi

# Create symlinks for all applets
echo "[1/5] Creating applet symlinks..."
COUNT=0
for applet in $("$HOST_BB" --list 2>/dev/null); do
    ln -sf busybox "$ROOTFS/bin/$applet" 2>/dev/null || true
    COUNT=$((COUNT + 1))
done
echo "       $COUNT applets linked"

# Create sbin links
echo "[2/5] Creating sbin links..."
for applet in init reboot poweroff halt shutdown ifconfig route ip modprobe depmod \
              mdev syslogd klogd mkswap swapon swapoff fdisk fsck mount umount \
              arp brctl vconfig ip6tables iptables; do
    ln -sf ../bin/busybox "$ROOTFS/sbin/$applet" 2>/dev/null || true
done

# Create usr links
for d in usr/bin usr/sbin; do
    ln -sf ../../bin/busybox "$ROOTFS/$d/busybox" 2>/dev/null || true
done

# /etc files
echo "[3/5] Generating /etc configs..."

cat > "$ROOTFS/etc/passwd" << 'EOF'
root::0:0:root:/root:/bin/sh
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF

cat > "$ROOTFS/etc/group" << 'EOF'
root:x:0:
daemon:x:1:
tty:x:5:
disk:x:6:
audio:x:29:
video:x:44:
users:x:100:
EOF

cat > "$ROOTFS/etc/shadow" << 'EOF'
root::19000:0:99999:7:::
EOF
chmod 600 "$ROOTFS/etc/shadow"

cat > "$ROOTFS/etc/hostname" << 'EOF'
superlite
EOF

cat > "$ROOTFS/etc/hosts" << 'EOF'
127.0.0.1 localhost superlite
::1       localhost ip6-localhost ip6-loopback
EOF

cat > "$ROOTFS/etc/fstab" << 'EOF'
proc      /proc  proc      defaults          0 0
sysfs     /sys   sysfs     defaults          0 0
devtmpfs  /dev   devtmpfs  defaults          0 0
tmpfs     /tmp   tmpfs     defaults,noatime  0 0
tmpfs     /run   tmpfs     defaults,noatime  0 0
EOF

cat > "$ROOTFS/etc/profile" << 'PROFILE'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export TERM=linux
export PS1='\033[1;31mSuperLite\033[0m:\w\$ '
alias ls='ls --color=auto'
alias ll='ls -la'
alias la='ls -a'
PROFILE

cat > "$ROOTFS/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

cat > "$ROOTFS/etc/nsswitch.conf" << 'EOF'
hosts: files dns
passwd: files
group: files
EOF

cat > "$ROOTFS/etc/motd" << 'EOF'

  ╔══════════════════════════════════╗
  ║     ⚡ SuperLite OS v0.1.0       ║
  ║   Ultra-lightweight Linux DE     ║
  ╚══════════════════════════════════╝

  Type 'busybox --list' for commands
  Architecture: __ARCH__

EOF
sed -i "s/__ARCH__/$ARCH/" "$ROOTFS/etc/motd"

# Create /init
echo "[4/5] Creating init script..."

cat > "$ROOTFS/init" << 'INIT'
#!/bin/sh

# SuperLite OS — initramfs init
# Auto-detects root filesystem and switches to it

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Mount virtual filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts 2>/dev/null
mount -t tmpfs tmpfs /dev/shm 2>/dev/null
mount -t tmpfs tmpfs /run 2>/dev/null

echo ""
echo "  ╔══════════════════════════════════╗"
echo "  ║     ⚡ SuperLite OS v0.1.0       ║"
echo "  ║   Ultra-lightweight Linux DE     ║"
echo "  ╚══════════════════════════════════╝"
echo ""

# Setup loopback
ifconfig lo 127.0.0.1 up 2>/dev/null

# Start syslog
syslogd -O /var/log/messages 2>/dev/null
klogd 2>/dev/null

# Try DHCP on available interfaces
for iface in eth0 wlan0 enp0s3 ens33; do
    if [ -d "/sys/class/net/$iface" ]; then
        echo "Trying DHCP on $iface..."
        ifconfig "$iface" up 2>/dev/null
        udhcpc -i "$iface" -n -q -t 5 2>/dev/null && break
    fi
done

# Search for SuperLite rootfs
echo "Searching for root filesystem..."
ROOT_FOUND=0

for dev in /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/mmcblk0p1 /dev/nvme0n1p1; do
    if [ -b "$dev" ]; then
        echo "  Trying $dev..."
        mount -t ext4 "$dev" /mnt 2>/dev/null && ROOT_TYPE="ext4" && ROOT_FOUND=1 && break
        mount -t vfat "$dev" /mnt 2>/dev/null && ROOT_TYPE="vfat" && ROOT_FOUND=1 && break
        mount -t ext3 "$dev" /mnt 2>/dev/null && ROOT_TYPE="ext3" && ROOT_FOUND=1 && break
    fi
done

if [ "$ROOT_FOUND" = "1" ]; then
    echo "  Root found on $dev ($ROOT_TYPE)"
    
    # Check for SuperLite
    if [ -d /mnt/usr/share/superlite ] || [ -f /mnt/sbin/init ] || [ -f /mnt/etc/inittab ]; then
        echo "  Switching to real root..."
        umount /proc 2>/dev/null
        umount /sys 2>/dev/null
        umount /dev 2>/dev/null
        exec switch_root /mnt /sbin/init
    else
        echo "  Device mounted but no valid rootfs found."
        umount /mnt 2>/dev/null
    fi
fi

# Also try LVM / LUKS
echo "Checking for LVM..."
vgchange -ay 2>/dev/null
for dev in /dev/mapper/*; do
    if [ -b "$dev" ]; then
        mount -t ext4 "$dev" /mnt 2>/dev/null && exec switch_root /mnt /sbin/init
    fi
done

# Fallback: rescue shell
echo ""
echo "No root filesystem found."
echo ""
echo "Block devices:"
cat /proc/partitions 2>/dev/null
echo ""
echo "Available mounts:"
cat /proc/mounts 2>/dev/null
echo ""
echo "Starting rescue shell..."
echo "  Manual: mount /dev/sdX1 /mnt && exec switch_root /mnt /sbin/init"
echo ""
exec /bin/sh
INIT
chmod +x "$ROOTFS/init"

# Create device nodes
echo "[5/5] Creating device nodes..."
for node in "null c 1 3" "zero c 1 5" "random c 1 8" "urandom c 1 9" \
            "tty c 5 0" "console c 5 1" "ptmx c 5 2" \
            "tty0 c 4 0" "tty1 c 4 1" "tty2 c 4 2" "tty3 c 4 3" "tty4 c 4 4"; do
    set -- $node
    mknod "$ROOTFS/dev/$1" "$2" "$3" "$4" 2>/dev/null || true
    chmod 666 "$ROOTFS/dev/$1" 2>/dev/null || true
done

# Pack into cpio
echo ""
echo "Packing initramfs..."
cd "$ROOTFS"
find . | cpio -o -H newc 2>/dev/null | gzip > "$OUTPUT"

SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || stat -f%z "$OUTPUT" 2>/dev/null)
echo ""
echo "============================================"
echo "  Build Complete"
echo "  Output: $OUTPUT"
echo "  Size: $((SIZE / 1024)) KB"
echo "  Architecture: $ARCH"
echo "  BusyBox: 1.37.0 (static, musl)"
echo "============================================"
echo ""
echo "QEMU test:"
echo "  qemu-system-$ARCH -kernel /boot/vmlinuz -initrd $OUTPUT \\"
echo "    -nographic -append 'console=ttyS0'"
echo ""
echo "Write to flashdisk:"
echo "  dd if=$OUTPUT of=/dev/sdX1 bs=4M status=progress"

# Cleanup
rm -rf "$WORKDIR"
