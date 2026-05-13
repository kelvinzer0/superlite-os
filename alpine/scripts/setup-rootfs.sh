#!/bin/sh
# ============================================================================
# SuperLite OS — Rootfs Setup Script
# Runs INSIDE Alpine chroot to configure the system
# ============================================================================
set -eu

echo "[setup] Configuring Alpine rootfs..."

# ── Repositories ──────────────────────────────────────────────────────────────
echo "[setup] Configuring repositories..."
cat > /etc/apk/repositories << 'EOF'
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF

apk update

# ── Upgrade base ──────────────────────────────────────────────────────────────
echo "[setup] Upgrading base system..."
apk upgrade --available

# ── Install packages ──────────────────────────────────────────────────────────
echo "[setup] Installing packages (this will take a while)..."
xargs apk add --no-cache < /tmp/packages.list 2>&1 | tail -5

# ── Enable services ──────────────────────────────────────────────────────────
echo "[setup] Enabling services..."
rc-update add bootmisc boot 2>/dev/null || true
rc-update add hostname boot 2>/dev/null || true
rc-update add swclock boot 2>/dev/null || true
rc-update add sysctl boot 2>/dev/null || true
rc-update add seedrng boot 2>/dev/null || true
rc-update add urandom boot 2>/dev/null || true

rc-update add devfs sysinit 2>/dev/null || true
rc-update add dmesg sysinit 2>/dev/null || true
rc-update add mdev sysinit 2>/dev/null || true
rc-update add hwdrivers sysinit 2>/dev/null || true
rc-update add modloop sysinit 2>/dev/null || true

rc-update add seatd default 2>/dev/null || true
rc-update add dbus default 2>/dev/null || true
rc-update add networkmanager default 2>/dev/null || true
rc-update add chronyd default 2>/dev/null || true
rc-update add tlp default 2>/dev/null || true
rc-update add sshd default 2>/dev/null || true

# ── Hostname ─────────────────────────────────────────────────────────────────
echo "superlite" > /etc/hostname
echo "127.0.0.1 localhost superlite" > /etc/hosts
echo "::1       localhost ip6-localhost ip6-loopback" >> /etc/hosts

# ── Auto-login on tty1 ──────────────────────────────────────────────────────
echo "[setup] Configuring auto-login..."
mkdir -p /etc/init.d

# Create agetty autologin override for tty1
mkdir -p /etc/conf.d
cat > /etc/conf.d/agetty.tty1 << 'EOF'
BAUDRATE="115200"
TERM="foot"
GETTY_ARGS="--autologin root --noclear"
EOF

# ── Create live user ─────────────────────────────────────────────────────────
echo "[setup] Creating live user..."
adduser -D -s /bin/bash -G wheel live
echo "live:live" | chpasswd
echo "live ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/live
chmod 440 /etc/sudoers.d/live

# ── Shell profiles ──────────────────────────────────────────────────────────
echo "[setup] Setting up shell profiles..."

cat > /etc/profile.d/xdg.sh << 'PROFILE'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1
PROFILE

# ── Copy dotfiles to /etc/skel ──────────────────────────────────────────────
echo "[setup] Installing dotfiles..."
if [ -d /tmp/dotfiles ]; then
    # Copy all dotfiles to skel
    cp -rT /tmp/dotfiles /etc/skel/ 2>/dev/null || cp -r /tmp/dotfiles/. /etc/skel/
    
    # Also copy to root home
    cp -rT /tmp/dotfiles /root/ 2>/dev/null || cp -r /tmp/dotfiles/. /root/
    
    # Set permissions
    find /etc/skel -name '*.sh' -exec chmod +x {} \; 2>/dev/null
    find /root -name '*.sh' -exec chmod +x {} \; 2>/dev/null
    chmod +x /etc/skel/.config/scripts/* 2>/dev/null
    chmod +x /root/.config/scripts/* 2>/dev/null
fi

# ── LabWC session for root auto-login ──────────────────────────────────────
echo "[setup] Configuring LabWC auto-start..."
cat > /root/.profile << 'ROOTPROFILE'
# SuperLite OS — root profile
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11

# Auto-start LabWC on tty1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec labwc
fi
ROOTPROFILE

# ── Boot splash / MOTD ────────────────────────────────────────────────────
cat > /etc/motd << 'EOF'

  ╔══════════════════════════════════════╗
  ║      ⚡ SuperLite OS                 ║
  ║   Alpine Linux + LabWC Wayland       ║
  ╚══════════════════════════════════════╝

EOF

# ── fstab ──────────────────────────────────────────────────────────────────
cat > /etc/fstab << 'EOF'
proc            /proc    proc     defaults              0 0
sysfs           /sys     sysfs    defaults              0 0
devtmpfs        /dev     devtmpfs defaults              0 0
tmpfs           /tmp     tmpfs    defaults,noatime      0 0
tmpfs           /run     tmpfs    defaults,noatime      0 0
EOF

# ── NetworkManager ─────────────────────────────────────────────────────────
echo "[setup] Configuring NetworkManager..."
cat > /etc/NetworkManager/NetworkManager.conf << 'EOF'
[main]
plugins=ifupdown,keyfile
dhcp=internal

[ifupdown]
managed=false

[device]
wifi.backend=wpa_supplicant
EOF

# ── Clean up ───────────────────────────────────────────────────────────────
echo "[setup] Cleaning up..."
rm -rf /tmp/packages.list /tmp/repositories /tmp/dotfiles /tmp/setup-rootfs.sh
apk cache clean 2>/dev/null
rm -rf /var/cache/apk/*

echo "[setup] Rootfs configuration complete!"
