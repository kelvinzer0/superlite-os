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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIGS_DIR=""
for _candidate in \
    "$SCRIPT_DIR/alpine/configs" \
    "$SCRIPT_DIR/../../alpine/configs" \
    "/build/alpine/configs" \
    "./alpine/configs"; do
    if [ -d "$_candidate" ] && [ -f "$_candidate/repositories" ]; then
        CONFIGS_DIR="$_candidate"
        break
    fi
done
if [ -z "$CONFIGS_DIR" ]; then
    echo "ERROR: alpine/configs directory not found" >&2
    exit 1
fi

mkdir -p "$tmp"/etc/apk
{
    echo "/media/cdrom/apks"
    cat "$CONFIGS_DIR/repositories"
} | makefile root:root 0644 "$tmp"/etc/apk/repositories

# ── Package world (for post-boot apk add) ─────────────────────────────────────
# Read from alpine/configs/packages.list, strip comments, blank lines, and
# exclude ISO-only boot packages (grub, syslinux, squashfs-tools, etc.)
sed '/# --- Boot (ISO only/,$d; s/#.*//; /^[[:space:]]*$/d' "$CONFIGS_DIR/packages.list" | makefile root:root 0644 "$tmp"/etc/apk/world

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
rc_add udev-trigger boot
rc_add udev-settle boot
rc_add udev-postmount boot

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

# ── agetty per-port symlinks (OpenRC requires port-specific symlinks) ────────
# NOTE: Auto-login is handled by inittab getty lines (-a root flag),
# so we do NOT add agetty to OpenRC runlevels to avoid double respawn.
# These symlinks are kept for manual use: rc-service agetty.tty1 start
mkdir -p "$tmp"/etc/runlevels/default

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

# ── Override /etc/inittab — OpenRC + auto-login getty ────────────────────────
makefile root:root 0644 "$tmp"/etc/inittab <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

# Auto-login as root on tty1 and serial console
tty1::respawn:/sbin/agetty -a root -L 115200 tty1 linux
ttyS0::respawn:/sbin/agetty -a root -L 115200 ttyS0 vt100

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
netdev:x:1000:
tape:x:1001:
EOF

# ── Copy dotfiles to skel + root ──────────────────────────────────────────────
# NOTE: Dotfiles are copied FIRST, then overlay files below overwrite as needed
DOTFILES_DIR="$SCRIPT_DIR/../../dotfiles"

if [ -d "$DOTFILES_DIR" ]; then
    mkdir -p "$tmp"/etc/skel
    # Copy config dotfiles (.config, .bashrc, .profile, etc.)
    for item in "$DOTFILES_DIR"/.*; do
        name="$(basename "$item")"
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        [ "$name" = "usr" ] && continue
        cp -a "$item" "$tmp"/etc/skel/
    done
    # Also to root
    mkdir -p "$tmp"/root
    for item in "$DOTFILES_DIR"/.*; do
        name="$(basename "$item")"
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        [ "$name" = "usr" ] && continue
        cp -a "$item" "$tmp"/root/
    done

    # Copy Pictures (wallpapers) to skel and root
    if [ -d "$DOTFILES_DIR/Pictures" ]; then
        cp -a "$DOTFILES_DIR/Pictures" "$tmp"/etc/skel/
        cp -a "$DOTFILES_DIR/Pictures" "$tmp"/root/
    fi

    # Copy system files (themes, fonts, icons) to /usr/share
    if [ -d "$DOTFILES_DIR/usr/share" ]; then
        mkdir -p "$tmp"/usr/share
        cp -a "$DOTFILES_DIR"/usr/share/* "$tmp"/usr/share/
    fi
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
# We use the dotfiles .profile as base and append only the LabWC auto-start block
mkdir -p "$tmp"/root

# Append LabWC auto-start + Wayland env to the dotfiles .profile
cat >> "$tmp"/root/.profile <<'EOF'

# ── Wayland environment (auto-generated by genapkovl) ────────────────────────
if test -z "${XDG_SESSION_TYPE}"; then
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=wlroots
    export XDG_SEAT=seat0
    export QT_QPA_PLATFORM=wayland
    export MOZ_ENABLE_WAYLAND=1
    export GDK_BACKEND=wayland,x11
fi

# Suppress libinput error in VMs (QEMU, no physical input devices)
[ -z "$WLR_LIBINPUT_NO_DEVICES" ] && export WLR_LIBINPUT_NO_DEVICES=1

# Auto-detect GPU driver
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER

# ── LabWC auto-start on tty1 ─────────────────────────────────────────────────
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

# ── MOTD (dynamic, generated at login) ───────────────────────────────────────
# Static placeholder — real MOTD is printed by /etc/profile.d/motd.sh
makefile root:root 0644 "$tmp"/etc/motd <<'EOF'
EOF

mkdir -p "$tmp"/etc/profile.d
makefile root:root 0755 "$tmp"/etc/profile.d/motd.sh <<'MOTDEOF'
#!/bin/sh
# Dynamic MOTD — SuperLite OS
# Only on interactive tty sessions
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac

KERNEL="$(uname -r)"
LAST_LOGIN="$(last -1 -F "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}')"
[ -z "$LAST_LOGIN" ] && LAST_LOGIN="$(date '+%Y-%m-%d %H:%M')"
LINE="$(printf '%0.0s─' $(seq 1 67))"

printf '\n'
printf '  Linux %-44s Last login: %s\n' "$KERNEL" "$LAST_LOGIN"
printf '  %s\n' "$LINE"
printf '  \042Stay curious. Break things responsibly.\042\n'
printf '  %s\n\n' "$LINE"
MOTDEOF

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
