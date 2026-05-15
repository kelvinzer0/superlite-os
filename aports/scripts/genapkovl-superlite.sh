#!/bin/sh -e
# ============================================================================
# SuperLite OS — Overlay Generator
# Generates the apkovl tarball that configures the live system.
# This is the Alpine-native way — no initramfs hacking needed.
# ============================================================================
# Reference: fvanniere/alpine-custom

HOSTNAME="$1"
if [ -z "$HOSTNAME" ]; then
    echo "usage: $0 hostname"
    exit 1
fi

cleanup() { rm -rf "$tmp"; }

makefile() {
    OWNER="$1"; PERMS="$2"; FILENAME="$3"
    cat > "$FILENAME"
    chown "$OWNER" "$FILENAME"
    chmod "$PERMS" "$FILENAME"
}

rc_add() {
    mkdir -p "$tmp"/etc/runlevels/"$2"
    ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

# ── Hostname ──────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc
makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF

# ── Network ───────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/network
makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF

# ── Repositories ──────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/apk
makefile root:root 0644 "$tmp"/etc/apk/repositories <<EOF
/media/cdrom/apks
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF

# ── Trust CDROM: copy all available apk signing keys ──────────────────────────
mkdir -p "$tmp"/etc/apk/keys
# Copy Alpine default keys
for _keydir in /etc/apk/keys /usr/share/apk/keys/x86_64; do
    [ -d "$_keydir" ] && cp "$_keydir"/* "$tmp"/etc/apk/keys/ 2>/dev/null || true
done
# Copy build signing key (so CDROM packages are trusted)
for _keyfile in /home/build/.abuild/*.pub /root/.abuild/*.pub; do
    [ -f "$_keyfile" ] && cp "$_keyfile" "$tmp"/etc/apk/keys/ 2>/dev/null || true
done

# ── Package world (for post-boot apk add) ─────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/apk/world <<EOF
alpine-base
openrc
busybox
busybox-suid
busybox-static
kmod
linux-lts
linux-virt
labwc
foot
mesa-dri-gallium
seatd
dbus
waybar
swaybg
swayidle
mako
tofi
brightnessctl
networkmanager
font-awesome
font-terminus
simp1e-cursors
gsettings-desktop-schemas
gammastep
sudo
lua5.4
EOF

# ── OpenRC services ───────────────────────────────────────────────────────────
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add networking boot
rc_add urandom boot
rc_add keymaps boot

rc_add seatd default
rc_add dbus default
rc_add networkmanager default
rc_add chronyd default
rc_add sshd default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

# ── Auto-login on tty1 ────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/conf.d
makefile root:root 0644 "$tmp"/etc/conf.d/agetty.tty1 <<EOF
BAUDRATE="115200"
TERM="foot"
GETTY_ARGS="--autologin root --noclear"
EOF

# ── Auto-login on serial console ──────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/conf.d/agetty.ttyS0 <<EOF
BAUDRATE="115200"
TERM="linux"
GETTY_ARGS="--autologin root --noclear"
EOF

# ── Create live user ──────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/sudoers.d
makefile root:root 0440 "$tmp"/etc/sudoers.d/live <<EOF
live ALL=(ALL) NOPASSWD: ALL
EOF

# ── Shell profiles (Wayland env) ──────────────────────────────────────────────
mkdir -p "$tmp"/etc/profile.d
makefile root:root 0755 "$tmp"/etc/profile.d/xdg.sh <<'EOF'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11
EOF

# ── LabWC auto-start for root ─────────────────────────────────────────────────
mkdir -p "$tmp"/root
makefile root:root 0644 "$tmp"/root/.profile <<'EOF'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11

if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec labwc
fi
EOF

# ── Hosts ─────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/hosts <<EOF
127.0.0.1 localhost $HOSTNAME
::1       localhost ip6-localhost ip6-loopback
EOF

# ── fstab ─────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/fstab <<EOF
proc            /proc    proc     defaults              0 0
sysfs           /sys     sysfs    defaults              0 0
devtmpfs        /dev     devtmpfs defaults              0 0
tmpfs           /tmp     tmpfs    defaults,noatime      0 0
tmpfs           /run     tmpfs    defaults,noatime      0 0
EOF

# ── Ensure /sbin/init exists ──────────────────────────────────────────────────
# Alpine's live boot with profile_virt may not have /sbin/init in the tmpfs rootfs.
# The apkovl overlay sets it up so the system can boot properly.
mkdir -p "$tmp"/sbin

# Create a proper init script that chains to OpenRC
makefile root:root 0755 "$tmp"/sbin/init <<'INITEOF'
#!/bin/sh
# SuperLite OS — Init wrapper
# Ensures /sbin/init exists for Alpine live boot

# Mount virtual filesystems if not already mounted
mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys  || mount -t sysfs sysfs /sys
mountpoint -q /dev  || mount -t devtmpfs devtmpfs /dev

# Load modules
for mod in loop squashfs overlay; do
    modprobe $mod 2>/dev/null
done

# Switch to OpenRC init
exec /sbin/openrc sysinit
INITEOF

# ── MOTD ──────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/motd <<'EOF'

  ╔══════════════════════════════════════╗
  ║      ⚡ SuperLite OS                 ║
  ║   Alpine Linux + LabWC Wayland       ║
  ╚══════════════════════════════════════╝

EOF

# ── NetworkManager config ─────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/NetworkManager
makefile root:root 0644 "$tmp"/etc/NetworkManager/NetworkManager.conf <<EOF
[main]
plugins=ifupdown,keyfile
dhcp=internal

[ifupdown]
managed=false

[device]
wifi.backend=wpa_supplicant
EOF

# ── Copy dotfiles to skel + root ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR/../../dotfiles"

if [ -d "$DOTFILES_DIR" ]; then
    mkdir -p "$tmp"/etc/skel
    # Copy all dotfiles
    (cd "$DOTFILES_DIR" && tar -cf - .) | (cd "$tmp"/etc/skel && tar -xf -)
    # Also to root
    mkdir -p "$tmp"/root
    (cd "$DOTFILES_DIR" && tar -cf - .) | (cd "$tmp"/root && tar -xf -)
fi

# ── Generate apkovl ───────────────────────────────────────────────────────────
tar -c -C "$tmp" etc root | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
echo "[overlay] Generated: $HOSTNAME.apkovl.tar.gz"
