#!/bin/bash
# SuperLite OS — Build & Run Script
# Usage: ./build-and-run.sh [--no-iso] [--no-vnc] [--port 6080]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="${HOME}/.superlite"
BUILD_DIR="${WORKSPACE}/build"
DRIVER_DUMP="${WORKSPACE}/driver-dump"
IMG="${BUILD_DIR}/superlite-os.img"
NOVNC_PORT="${NOVNC_PORT:-6080}"
BUILD_ISO=true
START_VNC=true

for arg in "$@"; do
    case "$arg" in
        --no-iso) BUILD_ISO=false ;;
        --no-vnc) START_VNC=false ;;
        --port=*) NOVNC_PORT="${arg#*=}" ;;
    esac
done

export PATH="/usr/sbin:/usr/bin:/bin:$PATH"
export PYTHONPATH="${SCRIPT_DIR}:${PYTHONPATH:-}"

echo "╔══════════════════════════════════════════╗"
echo "║       SuperLite OS Build Pipeline        ║"
echo "╚══════════════════════════════════════════╝"

# ─── Step 1: Dump host drivers ──────────────────────────
echo ""
echo "[1/5] Dumping host drivers..."
if [ -f "${DRIVER_DUMP}/manifest.json" ]; then
    echo "  → Using existing dump: ${DRIVER_DUMP}"
else
    python3 -c "
import sys; sys.path.insert(0, '${SCRIPT_DIR}')
from drivers.dump import DriverDump
d = DriverDump('${DRIVER_DUMP}')
d.dump_all()
"
fi

# ─── Step 2: Build rootfs via debootstrap ───────────────
echo ""
echo "[2/5] Building rootfs (debootstrap)..."
ROOTFS="${BUILD_DIR}/rootfs"

if [ ! -d "$ROOTFS/usr" ]; then
    debootstrap \
        --arch amd64 \
        --variant=minbase \
        --include systemd,systemd-sysv,dbus,dbus-x11,xorg,xserver-xorg-video-all,xserver-xorg-input-all,openbox,xinit,gir1.2-gtk-4.0,python3-gi,python3-gi-cairo,python3,python3-psutil,network-manager,pciutils,usbutils,bash,coreutils,util-linux,nano \
        --exclude man-db,manpages,info,doc-debian \
        bookworm \
        "$ROOTFS" \
        http://deb.debian.org/debian
else
    echo "  → Rootfs exists, skipping debootstrap"
fi

# ─── Step 3: Inject drivers + install DE ────────────────
echo ""
echo "[3/5] Injecting drivers + SuperLite DE..."

# Drivers
KERNEL=$(uname -r)
mkdir -p "$ROOTFS/lib/modules/$KERNEL"
cp -r "${DRIVER_DUMP}/modules/"* "$ROOTFS/lib/modules/$KERNEL/" 2>/dev/null || true
if [ -d "${DRIVER_DUMP}/firmware" ]; then
    mkdir -p "$ROOTFS/lib/firmware"
    cp -r "${DRIVER_DUMP}/firmware/"* "$ROOTFS/lib/firmware/" 2>/dev/null || true
fi

# SuperLite DE
SUPERLITE_DEST="$ROOTFS/usr/share/superlite"
mkdir -p "$SUPERLITE_DEST"
for item in core apps drivers assets utils; do
    [ -d "${SCRIPT_DIR}/$item" ] && cp -r "${SCRIPT_DIR}/$item" "$SUPERLITE_DEST/"
done
cp "${SCRIPT_DIR}/__init__.py" "${SCRIPT_DIR}/__main__.py" "$SUPERLITE_DEST/" 2>/dev/null || true

# Default config
mkdir -p "$ROOTFS/etc/superlite"
cp "${SCRIPT_DIR}/build/configs/default.json" "$ROOTFS/etc/superlite/config.json" 2>/dev/null || true

# Session launcher
cat > "$ROOTFS/usr/bin/superlite-session" << 'LAUNCHER'
#!/bin/bash
export XDG_CURRENT_DESKTOP=SuperLite
export DESKTOP_SESSION=superlite
export PYTHONPATH=/usr/share/superlite
cd /usr/share/superlite
exec python3 -m core.session
LAUNCHER
chmod +x "$ROOTFS/usr/bin/superlite-session"

# App launchers
for app in terminal:apps.terminal filemanager:apps.filemanager texteditor:apps.texteditor; do
    name="${app%%:*}"; module="${app##*:}"
    cat > "$ROOTFS/usr/bin/superlite-${name}" << APP
#!/bin/bash
cd /usr/share/superlite && python3 -m ${module}
APP
    chmod +x "$ROOTFS/usr/bin/superlite-${name}"
done

# ─── Step 4: Configure system (auto-login + X + DE) ─────
echo ""
echo "[4/5] Configuring auto-boot into DE..."

# Hostname
echo "superlite" > "$ROOTFS/etc/hostname"
echo "127.0.0.1 localhost superlite" > "$ROOTFS/etc/hosts"

# Fstab
cat > "$ROOTFS/etc/fstab" << 'FSTAB'
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /tmp tmpfs defaults,noatime 0 0
/dev/sda1 / ext4 defaults,errors=remount-ro 0 1
FSTAB

# Auto-login on tty1
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

# xinitrc — openbox + SuperLite DE
cat > "$ROOTFS/usr/share/superlite/xinitrc" << 'XINITRC'
#!/bin/bash
export DISPLAY=:0
export XDG_CURRENT_DESKTOP=SuperLite
export PYTHONPATH=/usr/share/superlite

xsetroot -solid "#0f0f23" 2>/dev/null &

# Openbox WM
openbox &
OB_PID=$!
sleep 1

# SuperLite DE
cd /usr/share/superlite
python3 -m core.session &
DE_PID=$!

wait $DE_PID
kill $OB_PID 2>/dev/null
XINITRC
chmod +x "$ROOTFS/usr/share/superlite/xinitrc"

# .bash_profile — auto-start X
cat > "$ROOTFS/root/.bash_profile" << 'BPROFILE'
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
BPROFILE

# Systemd service for X
cat > "$ROOTFS/etc/systemd/system/superlite-x.service" << 'SERVICE'
[Unit]
Description=SuperLite Desktop (X)
After=getty@tty1.service
ConditionPathExists=/usr/share/superlite/xinitrc

[Service]
Type=simple
User=root
Environment=DISPLAY=:0
Environment=XDG_VTNR=1
WorkingDirectory=/root
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/xinit /usr/share/superlite/xinitrc -- :0 vt1 -keeptty -nolisten tcp
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/superlite-x.service \
    "$ROOTFS/etc/systemd/system/multi-user.target.wants/superlite-x.service"

# Xorg config for QEMU
mkdir -p "$ROOTFS/etc/X11"
cat > "$ROOTFS/etc/X11/xorg.conf" << 'XORG'
Section "Device"
    Identifier "Default VGA"
    Driver "modesetting"
    Option "AccelMethod" "none"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "Default VGA"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1280x720" "1024x768" "800x600"
    EndSubSection
EndSection
XORG

# Install kernel in chroot
mount --bind /dev "$ROOTFS/dev" 2>/dev/null
mount --bind /proc "$ROOTFS/proc" 2>/dev/null
mount --bind /sys "$ROOTFS/sys" 2>/dev/null
mount --bind /etc/resolv.conf "$ROOTFS/etc/resolv.conf" 2>/dev/null

chroot "$ROOTFS" bash -c "
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq linux-image-amd64 2>&1 | tail -3
" 2>&1

umount "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/etc/resolv.conf" 2>/dev/null

# ─── Step 5: Build disk image ──────────────────────────
echo ""
echo "[5/5] Building disk image..."

dd if=/dev/zero of="$IMG" bs=1M count=2048 status=none
sfdisk -q "$IMG" << 'SFDISK'
label: dos
1 : type=83, bootable
SFDISK

LOOP=$(losetup --find --show --partscan "$IMG")
mkfs.ext4 -q -L SUPERLITE "${LOOP}p1"
MNT="/tmp/superlite-mnt"
mkdir -p "$MNT"
mount "${LOOP}p1" "$MNT"

echo "  Copying rootfs..."
cp -a "$ROOTFS/." "$MNT/"

echo "  Installing GRUB..."
mount --bind /dev "$MNT/dev"
mount --bind /proc "$MNT/proc"
mount --bind /sys "$MNT/sys"
chroot "$MNT" grub-install --target=i386-pc --boot-directory=/boot "$LOOP" 2>&1 | tail -2
chroot "$MNT" update-grub 2>&1 | tail -2
umount "$MNT/dev" "$MNT/proc" "$MNT/sys"

umount "$MNT"
losetup -d "$LOOP"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          Build Complete!                  ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Image: ${IMG}"
echo "║  Size:  $(du -h "$IMG" | cut -f1)"
echo "╚══════════════════════════════════════════╝"

# ─── Optional: Start QEMU + noVNC ──────────────────────
if [ "$START_VNC" = true ]; then
    echo ""
    echo "Starting QEMU + noVNC..."

    # Extract kernel for direct boot
    LOOP=$(losetup --find --show --partscan "$IMG")
    mount "${LOOP}p1" "$MNT"
    cp "$MNT/boot/vmlinuz-"* /tmp/superlite-vmlinuz 2>/dev/null || cp "$MNT/boot/vmlinuz" /tmp/superlite-vmlinuz
    cp "$MNT/boot/initrd.img-"* /tmp/superlite-initrd.img 2>/dev/null || true
    umount "$MNT"
    losetup -d "$LOOP"

    # Kill old instances
    pkill -f "qemu-system.*superlite" 2>/dev/null || true
    sleep 1

    qemu-system-x86_64 \
        -m 512 \
        -smp 1 \
        -kernel /tmp/superlite-vmlinuz \
        -initrd /tmp/superlite-initrd.img \
        -append "root=/dev/sda1 ro console=ttyS0 quiet" \
        -hda "$IMG" \
        -accel tcg \
        -vga virtio \
        -display none \
        -vnc :0 \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -monitor unix:/tmp/qemu-monitor.sock,server,nowait \
        -serial file:/tmp/qemu-serial.log \
        -daemonize

    sleep 1
    QPID=$(pgrep -f "qemu-system.*superlite" || pgrep qemu-system)
    echo "  QEMU PID: $QPID"

    # noVNC
    pkill -f "websockify.*6080" 2>/dev/null || true
    websockify --web=/usr/share/novnc "$NOVNC_PORT" localhost:5900 &>/tmp/websockify.log &

    # cloudflared
    pkill -f cloudflared 2>/dev/null || true
    cloudflared tunnel --url "http://localhost:$NOVNC_PORT" --no-autoupdate &>/tmp/cloudflared.log &
    sleep 5

    TUNNEL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log | head -1)

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              SuperLite OS — LIVE                         ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  noVNC:  http://localhost:${NOVNC_PORT}/vnc.html                ║"
    [ -n "$TUNNEL" ] && echo "║  Public: ${TUNNEL}  ║"
    echo "║                                                          ║"
    echo "║  Auto-login → X → SuperLite DE                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
fi
