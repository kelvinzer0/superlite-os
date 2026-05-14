#!/bin/sh
# ============================================================================
# SuperLite OS — Rootfs Setup Script
# Runs INSIDE Alpine chroot to configure the system
# ============================================================================
set -e

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
# Filter comments and empty lines, then install
# Use || true so missing optional packages don't abort the build
grep -v '^#' /tmp/packages.list | grep -v '^$' | xargs apk add 2>&1 | tail -5 || true
echo "[setup] Package installation complete (some optional packages may be unavailable)"

# ── Install external themes (OhSnap, Haiku, WhiteSur) ─────────────────────
echo "[setup] Installing external themes..."
if [ -f /tmp/hooks/install-themes.sh ]; then
    chmod +x /tmp/hooks/install-themes.sh
    (/tmp/hooks/install-themes.sh) || echo "[setup] WARNING: Theme install had issues (non-fatal)"
else
    echo "[setup] No theme installer found, skipping"
fi

# ── Firmware compression ─────────────────────────────────────────────────────
echo "[setup] Compressing firmware..."
if [ -f /tmp/hooks/compress-firmware.sh ]; then
    chmod +x /tmp/hooks/compress-firmware.sh
    # Run in subshell so failure doesn't abort the build
    (/tmp/hooks/compress-firmware.sh /lib/firmware) || echo "[setup] WARNING: Firmware compression had issues (non-fatal)"
fi

# ── Fix /sbin/init ────────────────────────────────────────────────────────────
echo "[setup] Fixing /sbin/init..."

# Ensure /sbin/init exists and is executable
# Alpine uses busybox init or openrc-init — make sure at least one works
if [ ! -e /sbin/init ]; then
    # Try to link to busybox init
    if [ -x /bin/busybox ]; then
        ln -sf /bin/busybox /sbin/init
        echo "[setup] Linked /sbin/init -> /bin/busybox"
    elif [ -x /sbin/openrc-init ]; then
        ln -sf /sbin/openrc-init /sbin/init
        echo "[setup] Linked /sbin/init -> /sbin/openrc-init"
    elif [ -x /sbin/openrc ]; then
        # Create a wrapper that calls openrc
        cat > /sbin/init << 'INITEOF'
#!/bin/sh
exec /sbin/openrc "$@"
INITEOF
        chmod +x /sbin/init
        echo "[setup] Created /sbin/init wrapper for openrc"
    else
        echo "[setup] WARNING: No init system found! Installing busybox-static..."
        apk add busybox-static 2>/dev/null || true
        if [ -x /bin/busybox ]; then
            ln -sf /bin/busybox /sbin/init
        fi
    fi
fi

# Verify /sbin/init is actually executable
if [ -e /sbin/init ] && [ ! -x /sbin/init ]; then
    chmod +x /sbin/init
    echo "[setup] Fixed /sbin/init permissions"
fi

# Double-check
if [ ! -x /sbin/init ]; then
    echo "[setup] CRITICAL: /sbin/init is not executable!"
    ls -la /sbin/init 2>/dev/null || echo "[setup] /sbin/init does not exist"
    # Last resort: install the init wrapper
    if [ -f /tmp/hooks/superlite-init-wrapper ]; then
        cp /tmp/hooks/superlite-init-wrapper /sbin/init
        chmod +x /sbin/init
        echo "[setup] Installed emergency init wrapper"
    fi
fi

echo "[setup] /sbin/init status: $(ls -la /sbin/init 2>/dev/null || echo 'MISSING')"

# ── mkinitfs configuration ───────────────────────────────────────────────────
echo "[setup] Configuring mkinitfs..."
mkdir -p /etc/mkinitfs
if [ -f /tmp/hooks/mkinitfs-superlite.conf ]; then
    cp /tmp/hooks/mkinitfs-superlite.conf /etc/mkinitfs/superlite.conf
fi

# Install the live-boot hook into mkinitfs features
mkdir -p /etc/mkinitfs/features.d
if [ -f /tmp/hooks/live-boot ]; then
    cp /tmp/hooks/live-boot /etc/mkinitfs/features.d/superlite-live
    chmod +x /etc/mkinitfs/features.d/superlite-live
fi

# Install the live init script for use by initramfs
if [ -f /tmp/hooks/superlite-live.init ]; then
    cp /tmp/hooks/superlite-live.init /etc/mkinitfs/superlite-live.init
    chmod +x /etc/mkinitfs/superlite-live.init
fi

# Regenerate initramfs with live-boot support
echo "[setup] Regenerating initramfs..."

# First, patch Alpine's init script for live-boot support
if [ -f /tmp/hooks/patch-init.sh ]; then
    echo "[setup] Patching Alpine init for live-boot..."
    chmod +x /tmp/hooks/patch-init.sh
    sh /tmp/hooks/patch-init.sh 2>&1 || echo "[setup] WARNING: init patch had issues (non-fatal)"
fi

KVER=$(ls /lib/modules/ 2>/dev/null | head -1 || echo "lts")
if [ -n "$KVER" ] && [ -d "/lib/modules/$KVER" ]; then
    mkinitfs -o /boot/initramfs-lts "$KVER" 2>&1 | tail -3 || \
        echo "[setup] WARNING: mkinitfs failed, will try later"
fi

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
mkdir -p /etc/init.d /etc/conf.d

cat > /etc/conf.d/agetty.tty1 << 'EOF'
BAUDRATE="115200"
TERM="foot"
GETTY_ARGS="--autologin root --noclear"
EOF

# ── Create live user ─────────────────────────────────────────────────────────
echo "[setup] Creating live user..."
adduser -D -s /bin/bash -G wheel live
echo "live:live" | chpasswd
mkdir -p /etc/sudoers.d
echo "live ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/live
chmod 440 /etc/sudoers.d/live

# ── Shell profiles ──────────────────────────────────────────────────────────
echo "[setup] Setting up shell profiles..."
cat > /etc/profile.d/xdg.sh << 'PROFILE'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11
PROFILE

# ── Copy dotfiles to /etc/skel ──────────────────────────────────────────────
echo "[setup] Installing dotfiles..."
if [ -d /tmp/dotfiles ]; then
    cp -rT /tmp/dotfiles /etc/skel/ 2>/dev/null || cp -r /tmp/dotfiles/. /etc/skel/
    cp -rT /tmp/dotfiles /root/ 2>/dev/null || cp -r /tmp/dotfiles/. /root/
    find /etc/skel -name '*.sh' -exec chmod +x {} \; 2>/dev/null
    find /root -name '*.sh' -exec chmod +x {} \; 2>/dev/null
    chmod +x /etc/skel/.config/scripts/* 2>/dev/null || true
    chmod +x /root/.config/scripts/* 2>/dev/null || true
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
mkdir -p /etc/NetworkManager
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

# Remove boot files that are copied to ISO separately (not needed in squashfs)
# Keep vmlinuz (needed by make-iso.sh to copy to ISO)
rm -f /boot/initramfs-lts /boot/System.map /boot/config-*
rm -rf /boot/grub

# Strip debug symbols from all shared libraries and binaries
find /usr/lib -name "*.so*" -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true
find /usr/bin /usr/sbin -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true

# Remove docs, man pages, locale, i18n
rm -rf /usr/share/man /usr/share/doc /usr/share/help /usr/share/gtk-doc
rm -rf /usr/share/i18n /usr/share/locale/*
rm -rf /usr/share/mime/packages/freedesktop.org.xml

# Remove pkgconfig, cmake, development files
rm -rf /usr/lib/pkgconfig /usr/lib/cmake /usr/include
rm -rf /usr/share/pkgconfig

# Remove APK cache and temp files
rm -rf /tmp/packages.list /tmp/repositories /tmp/dotfiles /tmp/setup-rootfs.sh /tmp/hooks /tmp/themes
apk cache clean 2>/dev/null
rm -rf /var/cache/apk/*

echo "[setup] Rootfs configuration complete!"
echo "[setup] Final /sbin/init: $(ls -la /sbin/init 2>/dev/null || echo 'MISSING')"
