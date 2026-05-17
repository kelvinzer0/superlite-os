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

cleanup() { 
    rm -rf "$tmp";
}

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

# ── Package world (for post-boot apk add) ─────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/apk/world <<EOF
alpine-base
openrc
busybox
busybox-suid
busybox-static
busybox-extras
kmod
linux-lts
linux-firmware-i915
linux-firmware-amdgpu
linux-firmware-amd-ucode
linux-firmware-ath10k
linux-firmware-rtlwifi
linux-firmware-rtw89
linux-firmware-rtl_bt
linux-firmware-brcm
linux-firmware-cirrus
linux-firmware-other
agetty
labwc
foot
mesa-dri-gallium
mesa-egl
mesa-gl
mesa-gbm
mesa-va-gallium
seatd
elogind
dbus
dbus-x11
waybar
swaybg
swayidle
mako
tofi
brightnessctl
networkmanager
font-awesome
font-terminus
font-dejavu
font-jetbrains-mono
font-tamzen
simp1e-cursors
gsettings-desktop-schemas
gammastep
pipewire
pipewire-alsa
pipewire-pulse
wireplumber
libnotify
polkit
sudo
lua5.4
xwayland
grim
slurp
wtype
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
rc_add elogind default
rc_add dbus default
rc_add polkitd default
rc_add networkmanager default
rc_add chronyd default
rc_add sshd default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

# ── Auto-login wrapper (for busybox getty fallback) ─────────────────────────
mkdir -p "$tmp"/usr/sbin
makefile root:root 0755 "$tmp"/usr/sbin/autologin <<'EOF'
#!/bin/sh
exec login -f root
EOF

# ── securetty — allow root login on these terminals ──────────────────────────
makefile root:root 0644 "$tmp"/etc/securetty <<'EOF'
tty1
ttyS0
EOF

# ── Auto-login on tty1 ────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/conf.d
makefile root:root 0644 "$tmp"/etc/conf.d/agetty.tty1 <<EOF
GETTY_ARGS="--autologin root --noclear 115200 tty1"
EOF

# ── Auto-login on serial console ──────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/conf.d/agetty.ttyS0 <<EOF
GETTY_ARGS="--autologin root --noclear 115200 ttyS0"
EOF

# ── Override /etc/inittab — disable busybox getty, use agetty service only ────
makefile root:root 0644 "$tmp"/etc/inittab <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

tty1::respawn:/sbin/agetty --autologin root --noclear 38400 tty1 linux
tty2::respawn:/sbin/agetty 38400 tty2 linux
tty3::respawn:/sbin/agetty 38400 tty3 linux
tty4::respawn:/sbin/agetty 38400 tty4 linux
tty5::respawn:/sbin/agetty 38400 tty5 linux
tty6::respawn:/sbin/agetty 38400 tty6 linux

ttyS0::respawn:/sbin/agetty --autologin root 115200 ttyS0 vt100

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

# ── Create live user ──────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/sudoers.d
makefile root:root 0440 "$tmp"/etc/sudoers.d/live <<EOF
live ALL=(ALL) NOPASSWD: ALL
EOF

# ── Seat/input group setup ────────────────────────────────────────────────────
# Create groups needed for seat management and input devices
mkdir -p "$tmp"/etc
makefile root:root 0644 "$tmp"/etc/group <<'EOF'
root:x:0:root
bin:x:1:root,bin,daemon
daemon:x:2:root,bin,daemon
sys:x:3:root,bin,adm
adm:x:4:root,adm,daemon
tty:x:5:
disk:x:6:root,adm
lp:x:7:daemon
mem:x:9:
kmem:x:10:
wheel:x:11:root
floppy:x:11:root
mail:x:12:postfix
news:x:13:
uucp:x:14:
audio:x:15:root
cdrom:x:16:root
dialout:x:18:root
ftp:x:21:
sshd:x:22:
input:x:23:root
kvm:x:34:root
video:x:36:root
games:x:35:
usb:x:43:
adm:x:4:root,adm,daemon
disk:x:6:root,adm
seat:x:480:root
seatd:x:481:root
messagebus:x:482:
polkitd:x:483:
EOF

# ── Copy dotfiles to skel + root ──────────────────────────────────────────────
# NOTE: Dotfiles are copied FIRST, then overlay files below overwrite as needed
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

# ── Shell profiles (Wayland env) ──────────────────────────────────────────────
mkdir -p "$tmp"/etc/profile.d
makefile root:root 0755 "$tmp"/etc/profile.d/xdg.sh <<'EOF'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11

# Suppress libinput error in VMs (QEMU, no physical input devices)
export WLR_LIBINPUT_NO_DEVICES=1

# Auto-detect GPU driver (don't hardcode Intel)
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER

# Ensure seatd socket is accessible
export XDG_SEAT=seat0
EOF

# ── LabWC auto-start for root (AFTER dotfiles to prevent overwrite) ──────────
# This MUST be the last file written to /root/ to ensure it's not overwritten
mkdir -p "$tmp"/root
makefile root:root 0644 "$tmp"/root/.profile <<'EOF'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export XDG_SEAT=seat0
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11

# Suppress libinput error in VMs (QEMU, no physical input devices)
[ -z "$WLR_LIBINPUT_NO_DEVICES" ] && export WLR_LIBINPUT_NO_DEVICES=1

# Auto-detect GPU driver
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER

# Source aliases from dotfiles if available
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

# Auto-start LabWC on tty1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    # Ensure seatd is running
    if ! pgrep -x seatd >/dev/null 2>&1; then
        sudo rc-service seatd start 2>/dev/null || true
        sleep 1
    fi
    # Start LabWC with dbus session
    exec dbus-run-session labwc
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

# ── Generate apkovl ───────────────────────────────────────────────────────────
tar -c -C "$tmp" etc root | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
echo "[overlay] Generated: $HOSTNAME.apkovl.tar.gz"
