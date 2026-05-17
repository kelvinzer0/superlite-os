#!/bin/sh -e
# ============================================================================
# SuperLite OS — Unified ISO Overlay
# Single ISO, 3 modes via boot menu:
#   superlite.desktop  → Live desktop
#   superlite.install  → Installer mode
#   superlite.parted   → Partition manager
#
# Boot mode is set via kernel cmdline: superlite.mode=desktop|install|parted
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

# ── Package world (merged from all lists, deduplicated) ──────────────────────
{
    for f in "$CONFIGS_DIR/packages.list" "$CONFIGS_DIR/packages-install.list" "$CONFIGS_DIR/packages-parted.list"; do
        [ -f "$f" ] && sed '/# --- Boot (ISO only/,$d; s/#.*//; /^[[:space:]]*$/d' "$f"
    done | sort -u
} | makefile root:root 0644 "$tmp"/etc/apk/world

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

# ── agetty ────────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/runlevels/default

# ── Auto-login ────────────────────────────────────────────────────────────────
mkdir -p "$tmp"/usr/sbin
makefile root:root 0755 "$tmp"/usr/sbin/autologin <<'EOF'
#!/bin/sh
exec login -f root
EOF

makefile root:root 0644 "$tmp"/etc/securetty <<'EOF'
tty1
ttyS0
EOF

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

# ── LabWC auto-start for desktop mode ────────────────────────────────────────
mkdir -p "$tmp"/root
cat >> "$tmp"/root/.profile <<'PROFILE_EOF'

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
PROFILE_EOF

# ── Boot mode detection & launcher ────────────────────────────────────────────
# Reads superlite.mode from kernel cmdline, launches appropriate mode
makefile root:root 0755 "$tmp"/etc/profile.d/00-boot-mode.sh <<'BOOTMODE_EOF'
#!/bin/sh
# SuperLite OS — Boot mode launcher
# Reads superlite.mode= from /proc/cmdline
# Modes: desktop (default), install, parted

case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac

# Only run on tty1
[ "$(tty)" != "/dev/tty1" ] && return 0 2>/dev/null || exit 0

# Prevent running twice
[ -f /tmp/.bootmode_done ] && return 0 2>/dev/null || exit 0
touch /tmp/.bootmode_done 2>/dev/null

# Read mode from kernel cmdline
MODE=""
for arg in $(cat /proc/cmdline 2>/dev/null); do
    case "$arg" in
        superlite.mode=*) MODE="${arg#superlite.mode=}" ;;
    esac
done

case "$MODE" in
    install)
        # ── Installer mode ───────────────────────────────────────────────
        clear
        echo ""
        echo "  SuperLite OS — Installation Mode"
        echo "  ─────────────────────────────────"
        echo ""
        exec /usr/local/bin/superlite-installer
        ;;
    parted)
        # ── Partition manager mode ───────────────────────────────────────
        clear
        echo ""
        echo "  SuperLite OS — Partition Manager"
        echo "  ─────────────────────────────────"
        echo ""
        exec /usr/local/bin/partman
        ;;
    desktop|"")
        # ── Desktop mode (default) ───────────────────────────────────────
        if ! pgrep -x seatd >/dev/null 2>&1; then
            sudo rc-service seatd start 2>/dev/null || true
            sleep 1
        fi
        exec dbus-run-session labwc
        ;;
    *)
        # Unknown mode — show menu
        ;;
esac
BOOTMODE_EOF

# ── Boot menu (fallback if no cmdline param) ──────────────────────────────────
makefile root:root 0755 "$tmp"/usr/local/bin/superlite-menu <<'MENU_EOF'
#!/bin/sh
# SuperLite OS — Boot Mode Menu
# Shown when no superlite.mode= kernel parameter is set

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

while true; do
    clear
    printf "${CYAN}${BOLD}"
    printf "  ╔══════════════════════════════════════════╗\n"
    printf "  ║           SuperLite OS                   ║\n"
    printf "  ║     Alpine · LabWC · Wayland             ║\n"
    printf "  ╠══════════════════════════════════════════╣\n"
    printf "  ║                                          ║\n"
    printf "  ║   ${GREEN}1${CYAN})  Desktop          ${BOLD}(live session)${NC}${CYAN}${BOLD}  ║\n"
    printf "  ║   ${GREEN}2${CYAN})  Install          ${BOLD}(partition + setup)${NC}${CYAN}${BOLD} ║\n"
    printf "  ║   ${GREEN}3${CYAN})  Partition Manager ${BOLD}(disk tools)${NC}${CYAN}${BOLD}  ║\n"
    printf "  ║   ${GREEN}4${CYAN})  Shell            ${BOLD}(bare terminal)${NC}${CYAN}${BOLD}  ║\n"
    printf "  ║                                          ║\n"
    printf "  ╚══════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "  Choose [1-4]: "
    read -r choice

    case "$choice" in
        1)
            if ! pgrep -x seatd >/dev/null 2>&1; then
                sudo rc-service seatd start 2>/dev/null || true
                sleep 1
            fi
            exec dbus-run-session labwc
            ;;
        2)
            exec /usr/local/bin/superlite-installer
            ;;
        3)
            exec /usr/local/bin/partman
            ;;
        4)
            exec /bin/sh
            ;;
        *)
            printf "  ${RED}Invalid choice${NC}\n"
            sleep 1
            ;;
    esac
done
MENU_EOF

# ── Dynamic MOTD ──────────────────────────────────────────────────────────────
makefile root:root 0755 "$tmp"/etc/profile.d/motd.sh <<'MOTDEOF'
#!/bin/sh
case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac

KERNEL="$(uname -r)"
LAST_LOGIN="$(last -1 -F "$USER" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7, $8}')"
[ -z "$LAST_LOGIN" ] && LAST_LOGIN="$(date '+%Y-%m-%d %H:%M')"
LINE="$(printf '%0.0s─' $(seq 1 67))"

# Detect boot mode
MODE=""
for arg in $(cat /proc/cmdline 2>/dev/null); do
    case "$arg" in superlite.mode=*) MODE="${arg#superlite.mode=}";; esac
done

printf '\n'
printf '  Linux %-44s Last login: %s\n' "$KERNEL" "$LAST_LOGIN"
printf '  %s\n' "$LINE"
printf '  "Stay curious. Break things responsibly."\n'
printf '  %s\n' "$LINE"

case "$MODE" in
    install) printf '  Mode: \033[1minstall\033[0m — Run \033[1msuperlite-installer\033[0m\n\n' ;;
    parted)  printf '  Mode: \033[1mparted\033[0m  — Run \033[1mpartman\033[0m\n\n' ;;
    *)       printf '  Mode: \033[1mdesktop\033[0m\n\n' ;;
esac
MOTDEOF

# ── TUI Installer ────────────────────────────────────────────────────────────
mkdir -p "$tmp"/usr/local/bin
makefile root:root 0755 "$tmp"/usr/local/bin/superlite-installer <<'INSTALLER_EOF'
#!/bin/sh
# ============================================================================
# SuperLite OS — TUI Installer
# ============================================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { printf "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${CYAN}${BOLD}  %s${NC}\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n" "$1"; }
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
info() { printf "  ${CYAN}→${NC} %s\n" "$1"; }
pause() { printf "\n  Press Enter to continue..."; read -r _; }
confirm() { printf "  ${BOLD}%s${NC} [y/N] " "$1"; read -r ans; case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac; }

show_disks() {
    header "Available Disks"
    lsblk -dno NAME,SIZE,MODEL,TYPE | grep -v loop | while read -r line; do printf "  %s\n" "$line"; done
    echo ""
}

partition_disk() {
    show_disks
    printf "  ${BOLD}Enter disk (e.g., sda, vda, nvme0n1):${NC} "
    read -r disk; dev="/dev/$disk"
    [ ! -b "$dev" ] && { fail "Device $dev not found"; return 1; }

    header "Partition $dev"
    printf "  ${YELLOW}WARNING: This will erase all data on $dev!${NC}\n\n"
    printf "  1) GPT (recommended)\n  2) MBR (legacy)\n  3) Custom (cfdisk)\n  4) Auto (EFI + swap + root)\n\n  Choose [1-4]: "
    read -r scheme
    case "$scheme" in
        1) parted -s "$dev" mklabel gpt; ok "GPT created"; cfdisk "$dev" ;;
        2) parted -s "$dev" mklabel msdos; ok "MBR created"; cfdisk "$dev" ;;
        3) cfdisk "$dev" ;;
        4) auto_partition "$dev" ;;
        *) fail "Invalid"; return 1 ;;
    esac
    ok "Partitioning complete"; lsblk "$dev"
}

auto_partition() {
    dev="$1"
    info "Auto-partitioning $dev (GPT: EFI + swap + root)"
    size_mb=$(blockdev --getsize64 "$dev" | awk '{printf "%.0f", $1/1024/1024}')
    wipefs -a "$dev" 2>/dev/null || true
    parted -s "$dev" mklabel gpt
    parted -s "$dev" mkpart ESP fat32 1MiB 513MiB
    parted -s "$dev" set 1 esp on
    swap_mb=$((size_mb / 10)); [ "$swap_mb" -gt 2048 ] && swap_mb=2048
    swap_end=$((513 + swap_mb))
    parted -s "$dev" mkpart primary linux-swap 513MiB "${swap_end}MiB"
    parted -s "$dev" mkpart primary ext4 "${swap_end}MiB" 100%
    case "$dev" in *nvme*) sep="p";; *) sep="";; esac
    info "Formatting..."; sleep 1
    mkfs.fat -F32 "${dev}${sep}1"
    mkswap "${dev}${sep}2"
    mkfs.ext4 -F "${dev}${sep}3"
    ok "EFI: ${dev}${sep}1 (512MB) | Swap: ${dev}${sep}2 (${swap_mb}MB) | Root: ${dev}${sep}3"
}

format_partitions() {
    header "Format Partition"
    show_disks
    printf "  ${BOLD}Partition (e.g., sda1):${NC} "
    read -r part; dev="/dev/$part"
    [ ! -b "$dev" ] && { fail "Not found"; return 1; }
    printf "  1)ext4 2)ext3 3)ext2 4)FAT32 5)NTFS 6)Btrfs 7)XFS 8)F2FS 9)Swap\n  Choose [1-9]: "
    read -r fs
    case "$fs" in
        1) mkfs.ext4 -F "$dev";; 2) mkfs.ext3 -F "$dev";; 3) mkfs.ext2 -F "$dev";;
        4) mkfs.fat -F32 "$dev";; 5) mkfs.ntfs -f "$dev";; 6) mkfs.btrfs -f "$dev";;
        7) mkfs.xfs -f "$dev";; 8) mkfs.f2fs -f "$dev";; 9) mkswap "$dev";;
        *) fail "Invalid"; return 1 ;;
    esac
    ok "Formatted $dev"
}

mount_partitions() {
    header "Mount Partitions"
    show_disks
    printf "  ${BOLD}Root partition (e.g., sda3):${NC} "
    read -r rp; mount "/dev/$rp" /mnt; ok "Root → /mnt"
    printf "  ${BOLD}EFI partition (empty to skip):${NC} "
    read -r ep; [ -n "$ep" ] && { mkdir -p /mnt/boot/efi; mount "/dev/$ep" /mnt/boot/efi; ok "EFI → /mnt/boot/efi"; }
    printf "  ${BOLD}Swap partition (empty to skip):${NC} "
    read -r sp; [ -n "$sp" ] && { swapon "/dev/$sp"; ok "Swap enabled"; }
}

install_system() {
    header "Install SuperLite OS"
    mountpoint -q /mnt || { fail "Mount partitions first (option 3)"; return 1; }
    info "Installing Alpine base..."; setup-disk /mnt
    [ -d /etc/skel ] && cp -a /etc/skel/.* /mnt/root/ 2>/dev/null || true
    cp /etc/motd /mnt/etc/motd 2>/dev/null || true
    ok "System installed to /mnt"
    info "Run 'reboot' to boot into installed system"
}

while true; do
    clear
    printf "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗\n  ║       SuperLite OS Installer             ║\n  ╚══════════════════════════════════════════╝${NC}\n\n"
    printf "  ${BOLD}Disk:${NC}  1) List  2) Partition  3) Format  4) Mount\n"
    printf "  ${BOLD}System:${NC} 5) Install  6) cfdisk  7) Shell\n"
    printf "  ${BOLD}Boot:${NC}  0) Reboot\n\n  Choose: "
    read -r c
    case "$c" in
        1) show_disks; pause ;; 2) partition_disk; pause ;; 3) format_partitions; pause ;;
        4) mount_partitions; pause ;; 5) install_system; pause ;; 6) cfdisk ;;
        7) /bin/sh ;; 0) reboot ;; *) warn "Invalid"; sleep 1 ;;
    esac
done
INSTALLER_EOF

# ── TUI Partition Manager ────────────────────────────────────────────────────
makefile root:root 0755 "$tmp"/usr/local/bin/partman <<'PARTMAN_EOF'
#!/bin/sh
# ============================================================================
# SuperLite OS — Partition Manager
# ============================================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

header() { printf "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${CYAN}${BOLD}  %s${NC}\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n" "$1"; }
ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${NC} %s\n" "$1"; }
info() { printf "  ${CYAN}→${NC} %s\n" "$1"; }
pause() { printf "\n  Press Enter to continue..."; read -r _; }
confirm() { printf "  ${BOLD}%s${NC} [y/N] " "$1"; read -r ans; case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac; }

list_disks() {
    header "Available Disks"
    printf "  ${BOLD}%-12s %-10s %-30s %-8s${NC}\n" "DEVICE" "SIZE" "MODEL" "TYPE"
    printf "  %s\n" "$(printf '─%.0s' $(seq 1 65))"
    lsblk -dno NAME,SIZE,MODEL,TYPE | grep -v loop | while read -r n s m t; do printf "  %-12s %-10s %-30s %-8s\n" "$n" "$s" "$m" "$t"; done
    echo ""
}

show_partitions() {
    header "Partitions"
    printf "  ${BOLD}%-15s %-10s %-10s %-15s %-20s${NC}\n" "PARTITION" "SIZE" "FSTYPE" "MOUNT" "LABEL"
    printf "  %s\n" "$(printf '─%.0s' $(seq 1 75))"
    lsblk -no NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL | grep -v "^loop" | while read -r n s f m l; do
        printf "  %-15s %-10s %-10s %-15s %-20s\n" "$n" "$s" "${f:-—}" "${m:-—}" "${l:-—}"
    done
    echo ""
}

create_partition() {
    header "Create Partition"
    list_disks
    printf "  ${BOLD}Target disk:${NC} " && read -r disk && dev="/dev/$disk"
    [ ! -b "$dev" ] && { fail "Not found"; return 1; }
    pttype=$(blkid -s PTTYPE -o value "$dev" 2>/dev/null || echo "none")
    info "Partition table: $pttype"
    printf "  1) GPT  2) MBR  3) Keep existing\n  Choose [1-3]: " && read -r pt
    case "$pt" in
        1) confirm "Create GPT on $dev?" && { parted -s "$dev" mklabel gpt; ok "GPT"; } ;;
        2) confirm "Create MBR on $dev?" && { parted -s "$dev" mklabel msdos; ok "MBR"; } ;;
        3) ;;
    esac
    info "Current partitions:"; parted -s "$dev" print free 2>/dev/null | tail -n +3
    printf "  ${BOLD}Start:${NC} " && read -r start; [ "$start" = "auto" ] && start="1MiB"
    printf "  ${BOLD}End:${NC} " && read -r end; [ "$end" = "100%" ] && end="100%"
    printf "  1)ext4 2)ext3 3)ext2 4)FAT32 5)NTFS 6)Btrfs 7)XFS 8)F2FS 9)swap 10)none\n  Choose: " && read -r fc
    case "$fc" in
        1) fs="ext4"; mk="mkfs.ext4 -F";; 2) fs="ext3"; mk="mkfs.ext3 -F";; 3) fs="ext2"; mk="mkfs.ext2 -F";;
        4) fs="fat32"; mk="mkfs.fat -F32";; 5) fs="ntfs"; mk="mkfs.ntfs -f";; 6) fs="btrfs"; mk="mkfs.btrfs -f";;
        7) fs="xfs"; mk="mkfs.xfs -f";; 8) fs="f2fs"; mk="mkfs.f2fs -f";; 9) fs="swap"; mk="mkswap";;
        10) fs=""; mk="";; *) fail "Invalid"; return 1;;
    esac
    printf "  ${BOLD}Label (optional):${NC} " && read -r label
    pnum=$(parted -s "$dev" print 2>/dev/null | grep -c "^[[:space:]]*[0-9]" || echo 0); pnum=$((pnum + 1))
    parted -s "$dev" mkpart primary "$start" "$end"
    case "$dev" in *nvme*) pd="${dev}p${pnum}";; *) pd="${dev}${pnum}";; esac
    sleep 1; [ -n "$mk" ] && $mk "$pd"
    [ -n "$label" ] && case "$fs" in ext4|ext3|ext2) e2label "$pd" "$label";; fat32) fatlabel "$pd" "$label";; esac
    ok "Created $pd"; lsblk "$pd" 2>/dev/null || true
}

delete_partition() {
    header "Delete Partition"; show_partitions
    printf "  ${BOLD}Partition:${NC} " && read -r part && dev="/dev/$part"
    [ ! -b "$dev" ] && { fail "Not found"; return 1; }
    parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1); num=$(echo "$part" | grep -o '[0-9]*$')
    mountpoint -q "$dev" 2>/dev/null && { warn "Mounted"; confirm "Unmount?" && umount "$dev" || { fail "Cannot delete"; return 1; }; }
    confirm "DELETE $dev?" && { parted -s "/dev/$parent" rm "$num"; ok "Deleted $dev"; }
}

resize_partition() {
    header "Resize Partition"; show_partitions
    printf "  ${BOLD}Partition:${NC} " && read -r part && dev="/dev/$part"
    [ ! -b "$dev" ] && { fail "Not found"; return 1; }
    parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1); num=$(echo "$part" | grep -o '[0-9]*$')
    printf "  ${BOLD}New size:${NC} " && read -r ns
    mountpoint -q "$dev" 2>/dev/null && umount "$dev"
    parted -s "/dev/$parent" resizepart "$num" "$ns"; ok "Resized"
    fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null)
    confirm "Resize $fstype filesystem?" && case "$fstype" in
        ext4|ext3|ext2) resize2fs "$dev";; btrfs) btrfs filesystem resize max "$dev";; xfs) xfs_growfs "$dev";; esac
}

auto_partition() {
    header "Auto Partition (EFI + swap + root)"; list_disks
    printf "  ${BOLD}Disk:${NC} " && read -r disk && dev="/dev/$disk"
    [ ! -b "$dev" ] && { fail "Not found"; return 1; }
    confirm "ERASE $dev completely?" || { info "Cancelled"; return 0; }
    size_mb=$(blockdev --getsize64 "$dev" | awk '{printf "%.0f", $1/1024/1024}')
    wipefs -a "$dev" 2>/dev/null || true; parted -s "$dev" mklabel gpt
    parted -s "$dev" mkpart ESP fat32 1MiB 513MiB; parted -s "$dev" set 1 esp on
    swap_mb=$((size_mb / 10)); [ "$swap_mb" -gt 2048 ] && swap_mb=2048; swap_end=$((513 + swap_mb))
    parted -s "$dev" mkpart primary linux-swap 513MiB "${swap_end}MiB"
    parted -s "$dev" mkpart primary ext4 "${swap_end}MiB" 100%
    case "$dev" in *nvme*) s="p";; *) s="";; esac; sleep 1
    mkfs.fat -F32 "${dev}${s}1"; mkswap "${dev}${s}2"; mkfs.ext4 -F "${dev}${s}3"
    ok "EFI:${dev}${s}1 | Swap:${dev}${s}2 (${swap_mb}MB) | Root:${dev}${s}3"
    lsblk "$dev"
}

wipe_disk() {
    header "Wipe Disk"; list_disks
    printf "  ${BOLD}Disk:${NC} " && read -r disk && dev="/dev/$disk"
    [ ! -b "$dev" ] && { fail "Not found"; return 1; }
    printf "  Type ${BOLD}YES${NC}: " && read -r c; [ "$c" != "YES" ] && { info "Cancelled"; return 0; }
    wipefs -a "$dev"; dd if=/dev/zero of="$dev" bs=1M count=1 2>/dev/null; ok "Wiped $dev"
}

benchmark_disk() {
    header "Benchmark"; printf "  ${BOLD}Partition:${NC} " && read -r part && dev="/dev/$part"
    [ ! -b "$dev" ] && { fail "Not found"; return 1; }
    tm="/tmp/bench_$$"; mkdir -p "$tm"; mount "$dev" "$tm" 2>/dev/null || true
    info "Write 128MB..."; dd if=/dev/zero of="$tm/.bench" bs=1M count=128 conv=fdatasync 2>&1 | grep -E "bytes|copied"
    info "Read 128MB..."; dd if="$tm/.bench" of=/dev/null bs=1M 2>&1 | grep -E "bytes|copied"
    rm -f "$tm/.bench"; umount "$tm" 2>/dev/null; rmdir "$tm" 2>/dev/null; ok "Done"
}

while true; do
    clear
    printf "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗\n  ║       SuperLite Partition Manager        ║\n  ╚══════════════════════════════════════════╝${NC}\n\n"
    printf "  ${BOLD}View:${NC}    1) Disks  2) Partitions  3) Info\n"
    printf "  ${BOLD}Modify:${NC}  4) Create  5) Delete  6) Resize  7) Auto\n"
    printf "  ${BOLD}FS:${NC}     8) Mount  9) Unmount  10) Wipe  11) Benchmark\n"
    printf "  ${BOLD}Tools:${NC}  12) cfdisk  13) sgdisk  14) Shell\n"
    printf "  ${BOLD}Boot:${NC}   0) Shutdown\n\n  Choose: "
    read -r c
    case "$c" in
        1) list_disks; pause ;; 2) show_partitions; pause ;; 3)
            header "Info"; printf "  Device: " && read -r d && echo "" && lsblk -f "/dev/$d" && blkid "/dev/$d" && pause ;;
        4) create_partition; pause ;; 5) delete_partition; pause ;; 6) resize_partition; pause ;;
        7) auto_partition; pause ;; 8)
            printf "  Partition: " && read -r p && printf "  Mount at: " && read -r m && mkdir -p "$m" && mount "/dev/$p" "$m" && ok "Mounted"; pause ;;
        9) printf "  Target: " && read -r t && umount "$t" && ok "Unmounted"; pause ;;
        10) wipe_disk; pause ;; 11) benchmark_disk; pause ;;
        12) cfdisk ;; 13) sgdisk ;; 14) /bin/sh ;; 0) poweroff ;; *) warn "Invalid"; sleep 1 ;;
    esac
done
PARTMAN_EOF

# ── MOTD ──────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/motd <<'EOF'

        ╲╲╲╲
       ╲╲╲╲╲╲
      ╲╲    ╲╲
     ╲╲      ╲╲          superlite
    ╲╲        ╲╲         ──────────────────────────────────
   ╲╲    ╱╲    ╲╲        Alpine · LabWC · Wayland
  ╲╲    ╱  ╲    ╲╲
 ╲╲    ╱    ╲    ╲╲      desktop · install · partition manager
╱╱╱   ╱      ╲   ╲╲╲
      ╱        ╲

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
