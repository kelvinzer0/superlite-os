#!/bin/sh -e
# ============================================================================
# SuperLite OS — Installation ISO Overlay Generator
# Full desktop + disk partitioning + TUI installer
# ============================================================================

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

# ── Package world ─────────────────────────────────────────────────────────────
sed '/# --- Boot (ISO only/,$d; s/#.*//; /^[[:space:]]*$/d' "$CONFIGS_DIR/packages-install.list" | makefile root:root 0644 "$tmp"/etc/apk/world

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

# ── agetty symlinks ───────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/runlevels/default

# ── Auto-login wrapper ───────────────────────────────────────────────────────
mkdir -p "$tmp"/usr/sbin
makefile root:root 0755 "$tmp"/usr/sbin/autologin <<'EOF'
#!/bin/sh
exec login -f root
EOF

# ── securetty ─────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/securetty <<'EOF'
tty1
ttyS0
EOF

# ── Auto-login config ─────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/conf.d
makefile root:root 0644 "$tmp"/etc/conf.d/agetty.tty1 <<EOF
GETTY_ARGS="--autologin root --noclear 115200 tty1"
EOF

makefile root:root 0644 "$tmp"/etc/conf.d/agetty.ttyS0 <<EOF
GETTY_ARGS="--autologin root --noclear 115200 ttyS0"
EOF

# ── inittab ───────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/inittab <<'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

tty1::respawn:/sbin/agetty -a root -L 115200 tty1 linux
ttyS0::respawn:/sbin/agetty -a root -L 115200 ttyS0 vt100

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

# ── sudoers ───────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/sudoers.d
makefile root:root 0440 "$tmp"/etc/sudoers.d/live <<EOF
live ALL=(ALL) NOPASSWD: ALL
EOF

# ── Groups ────────────────────────────────────────────────────────────────────
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
seat:x:480:root
seatd:x:481:root
messagebus:x:482:
polkitd:x:483:
netdev:x:1000:
tape:x:1001:
EOF

# ── Copy dotfiles ─────────────────────────────────────────────────────────────
DOTFILES_DIR="$SCRIPT_DIR/../../dotfiles"

if [ -d "$DOTFILES_DIR" ]; then
    mkdir -p "$tmp"/etc/skel
    for item in "$DOTFILES_DIR"/.*; do
        name="$(basename "$item")"
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        [ "$name" = "usr" ] && continue
        cp -a "$item" "$tmp"/etc/skel/
    done
    mkdir -p "$tmp"/root
    for item in "$DOTFILES_DIR"/.*; do
        name="$(basename "$item")"
        [ "$name" = "." ] || [ "$name" = ".." ] && continue
        [ "$name" = "usr" ] && continue
        cp -a "$item" "$tmp"/root/
    done
    if [ -d "$DOTFILES_DIR/usr/share" ]; then
        mkdir -p "$tmp"/usr/share
        cp -a "$DOTFILES_DIR"/usr/share/* "$tmp"/usr/share/
    fi

    # Copy Pictures (wallpapers) to skel and root
    if [ -d "$DOTFILES_DIR/Pictures" ]; then
        cp -a "$DOTFILES_DIR/Pictures" "$tmp"/etc/skel/
        cp -a "$DOTFILES_DIR/Pictures" "$tmp"/root/
    fi
fi

# ── Shell profiles ────────────────────────────────────────────────────────────
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
export WLR_LIBINPUT_NO_DEVICES=1
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER
export XDG_SEAT=seat0
EOF

# ── LabWC auto-start ─────────────────────────────────────────────────────────
mkdir -p "$tmp"/root
cat >> "$tmp"/root/.profile <<'EOF'

# ── Wayland environment ──────────────────────────────────────────────────────
if test -z "${XDG_SESSION_TYPE}"; then
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=wlroots
    export XDG_SEAT=seat0
    export QT_QPA_PLATFORM=wayland
    export MOZ_ENABLE_WAYLAND=1
    export GDK_BACKEND=wayland,x11
fi
[ -z "$WLR_LIBINPUT_NO_DEVICES" ] && export WLR_LIBINPUT_NO_DEVICES=1
unset LIBVA_DRIVER_NAME
unset VDPAU_DRIVER

# ── LabWC auto-start on tty1 ─────────────────────────────────────────────────
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    if ! pgrep -x seatd >/dev/null 2>&1; then
        sudo rc-service seatd start 2>/dev/null || true
        sleep 1
    fi
    exec dbus-run-session labwc
fi
EOF

# ── TUI Installer Script ─────────────────────────────────────────────────────
mkdir -p "$tmp"/usr/local/bin
makefile root:root 0755 "$tmp"/usr/local/bin/superlite-installer <<'INSTALLER_EOF'
#!/bin/sh
# ============================================================================
# SuperLite OS — TUI Installer
# Disk partitioning + system installation
# ============================================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

header() {
    printf "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${CYAN}${BOLD}  %s${NC}\n" "$1"
    printf "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
info() { printf "  ${CYAN}→${NC} %s\n" "$1"; }

pause() { printf "\n  Press Enter to continue..."; read -r _; }

confirm() {
    printf "  ${BOLD}%s${NC} [y/N] " "$1"
    read -r ans
    case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

# ── Main Menu ─────────────────────────────────────────────────────────────────
show_disks() {
    header "Available Disks"
    lsblk -dno NAME,SIZE,MODEL,TYPE | grep -E 'disk|loop' | while read -r line; do
        printf "  %s\n" "$line"
    done
    echo ""
}

partition_disk() {
    show_disks
    printf "  ${BOLD}Enter disk to partition (e.g., sda, vda, nvme0n1):${NC} "
    read -r disk
    dev="/dev/$disk"

    if [ ! -b "$dev" ]; then
        fail "Device $dev not found"
        return 1
    fi

    header "Partition $dev"
    printf "  ${YELLOW}WARNING: This will erase all data on $dev!${NC}\n\n"

    printf "  Partition scheme:\n"
    printf "    1) GPT (recommended for UEFI)\n"
    printf "    2) MBR (legacy BIOS)\n"
    printf "    3) Custom (launch cfdisk)\n"
    printf "    4) Auto partition (GPT: EFI + swap + root)\n\n"
    printf "  Choose [1-4]: "
    read -r scheme

    case "$scheme" in
        1)
            info "Creating GPT partition table on $dev"
            parted -s "$dev" mklabel gpt
            ok "GPT label created"
            info "Launching cfdisk for manual partitioning..."
            pause
            cfdisk "$dev"
            ;;
        2)
            info "Creating MBR partition table on $dev"
            parted -s "$dev" mklabel msdos
            ok "MBR label created"
            info "Launching cfdisk for manual partitioning..."
            pause
            cfdisk "$dev"
            ;;
        3)
            info "Launching cfdisk..."
            cfdisk "$dev"
            ;;
        4)
            auto_partition "$dev"
            ;;
        *)
            fail "Invalid choice"
            return 1
            ;;
    esac

    ok "Partitioning complete"
    lsblk "$dev"
}

auto_partition() {
    dev="$1"
    info "Auto-partitioning $dev (GPT: EFI + swap + root)"

    # Detect size
    size_mb=$(blockdev --getsize64 "$dev" | awk '{printf "%.0f", $1/1024/1024}')

    # Wipe
    wipefs -a "$dev" 2>/dev/null || true
    parted -s "$dev" mklabel gpt

    # EFI partition (512MB)
    parted -s "$dev" mkpart ESP fat32 1MiB 513MiB
    parted -s "$dev" set 1 esp on

    # Swap (2GB or 10% of disk, whichever is smaller)
    swap_mb=$((size_mb / 10))
    [ "$swap_mb" -gt 2048 ] && swap_mb=2048
    swap_end=$((513 + swap_mb))
    parted -s "$dev" mkpart primary linux-swap 513MiB "${swap_end}MiB"

    # Root (rest)
    parted -s "$dev" mkpart primary ext4 "${swap_end}MiB" 100%

    # Format
    # Handle nvme naming (nvme0n1p1 vs sda1)
    case "$dev" in
        *nvme*) sep="p" ;;
        *) sep="" ;;
    esac

    info "Formatting partitions..."
    mkfs.fat -F32 "${dev}${sep}1"
    mkswap "${dev}${sep}2"
    mkfs.ext4 -F "${dev}${sep}3"

    ok "EFI:   ${dev}${sep}1 (512MB, FAT32)"
    ok "Swap:  ${dev}${sep}2 (${swap_mb}MB)"
    ok "Root:  ${dev}${sep}3 (ext4)"
}

format_partitions() {
    header "Format Partitions"
    show_disks
    printf "  ${BOLD}Enter partition to format (e.g., sda1, nvme0n1p1):${NC} "
    read -r part
    dev="/dev/$part"

    if [ ! -b "$dev" ]; then
        fail "Partition $dev not found"
        return 1
    fi

    printf "  Filesystem:\n"
    printf "    1) ext4\n"
    printf "    2) ext3\n"
    printf "    3) ext2\n"
    printf "    4) FAT32\n"
    printf "    5) NTFS\n"
    printf "    6) Btrfs\n"
    printf "    7) XFS\n"
    printf "    8) F2FS\n"
    printf "    9) Swap\n\n"
    printf "  Choose [1-9]: "
    read -r fs

    case "$fs" in
        1) mkfs.ext4 -F "$dev" ;;
        2) mkfs.ext3 -F "$dev" ;;
        3) mkfs.ext2 -F "$dev" ;;
        4) mkfs.fat -F32 "$dev" ;;
        5) mkfs.ntfs -f "$dev" ;;
        6) mkfs.btrfs -f "$dev" ;;
        7) mkfs.xfs -f "$dev" ;;
        8) mkfs.f2fs -f "$dev" ;;
        9) mkswap "$dev" ;;
        *) fail "Invalid"; return 1 ;;
    esac

    ok "Formatted $dev"
}

mount_partitions() {
    header "Mount Partitions"
    show_disks

    printf "  ${BOLD}Root partition (e.g., sda3):${NC} "
    read -r root_part
    mount "/dev/$root_part" /mnt
    ok "Root mounted at /mnt"

    printf "  ${BOLD}EFI partition (e.g., sda1, leave empty to skip):${NC} "
    read -r efi_part
    if [ -n "$efi_part" ]; then
        mkdir -p /mnt/boot/efi
        mount "/dev/$efi_part" /mnt/boot/efi
        ok "EFI mounted at /mnt/boot/efi"
    fi

    printf "  ${BOLD}Swap partition (e.g., sda2, leave empty to skip):${NC} "
    read -r swap_part
    if [ -n "$swap_part" ]; then
        swapon "/dev/$swap_part"
        ok "Swap enabled"
    fi
}

install_system() {
    header "Install SuperLite OS"

    if ! mountpoint -q /mnt; then
        fail "Root partition not mounted at /mnt"
        info "Mount partitions first (option 3)"
        return 1
    fi

    info "Installing Alpine base system..."
    setup-disk /mnt

    info "Copying SuperLite overlay..."
    # Copy current live system config to installed system
    if [ -d /etc/skel ]; then
        cp -a /etc/skel/.* /mnt/root/ 2>/dev/null || true
    fi

    # Copy MOTD
    cp /etc/motd /mnt/etc/motd 2>/dev/null || true

    ok "System installed to /mnt"
    info "Run 'reboot' to boot into installed system"
}

show_menu() {
    clear
    printf "${BOLD}${CYAN}"
    printf "  ╔══════════════════════════════════════════╗\n"
    printf "  ║       SuperLite OS Installer             ║\n"
    printf "  ║       Disk Partition & Install           ║\n"
    printf "  ╚══════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "  ${BOLD}Disk Operations:${NC}\n"
    printf "    1) List disks\n"
    printf "    2) Partition disk\n"
    printf "    3) Format partition\n"
    printf "    4) Mount partitions\n"
    printf "\n"
    printf "  ${BOLD}System:${NC}\n"
    printf "    5) Install system\n"
    printf "    6) Launch cfdisk (manual)\n"
    printf "    7) Launch parted (manual)\n"
    printf "    8) Open shell\n"
    printf "\n"
    printf "    0) Reboot\n"
    printf "\n"
    printf "  Choose [0-8]: "
}

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
    show_menu
    read -r choice
    case "$choice" in
        1) show_disks; pause ;;
        2) partition_disk; pause ;;
        3) format_partitions; pause ;;
        4) mount_partitions; pause ;;
        5) install_system; pause ;;
        6) cfdisk ;;
        7) parted ;;
        8) /bin/sh ;;
        0) reboot ;;
        *) warn "Invalid choice"; sleep 1 ;;
    esac
done
INSTALLER_EOF

# ── MOTD ──────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/motd <<'EOF'

        ╲╲╲╲
       ╲╲╲╲╲╲
      ╲╲    ╲╲
     ╲╲      ╲╲          superlite install
    ╲╲        ╲╲         ──────────────────────────────────
   ╲╲    ╱╲    ╲╲        Alpine · LabWC · Wayland · Installer
  ╲╲    ╱  ╲    ╲╲
 ╲╲    ╱    ╲    ╲╲      run: superlite-installer
╱╱╱   ╱      ╲   ╲╲╲
      ╱        ╲

EOF

# ── Dynamic MOTD ──────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/profile.d
makefile root:root 0755 "$tmp"/etc/profile.d/motd.sh <<'MOTDEOF'
#!/bin/sh
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac
KERNEL="$(uname -r)"
LAST_LOGIN="$(last -1 -F "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}')"
[ -z "$LAST_LOGIN" ] && LAST_LOGIN="$(date '+%Y-%m-%d %H:%M')"
LINE="$(printf '%0.0s─' $(seq 1 67))"
printf '\n'
printf '  Linux %-44s Last login: %s\n' "$KERNEL" "$LAST_LOGIN"
printf '  %s\n' "$LINE"
printf '  "Stay curious. Break things responsibly."\n'
printf '  %s\n\n' "$LINE"
printf '  Run \033[1msuperlite-installer\033[0m to install the system.\n\n'
MOTDEOF

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

# ── /sbin/init ────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/sbin
makefile root:root 0755 "$tmp"/sbin/init <<'INITEOF'
#!/bin/sh
mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys  || mount -t sysfs sysfs /sys
mountpoint -q /dev  || mount -t devtmpfs devtmpfs /dev
for mod in loop squashfs overlay; do modprobe $mod 2>/dev/null; done
exec /sbin/openrc sysinit
INITEOF

# ── NetworkManager ────────────────────────────────────────────────────────────
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
tar -c -C "$tmp" etc root usr | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
echo "[overlay] Generated: $HOSTNAME.apkovl.tar.gz"
