#!/bin/sh -e
# ============================================================================
# SuperLite OS — Disk Partition Management ISO Overlay
# Minimal bootable environment for partition CRUD operations
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
sed '/# --- Boot (ISO only/,$d; s/#.*//; /^[[:space:]]*$/d' "$CONFIGS_DIR/packages-parted.list" | makefile root:root 0644 "$tmp"/etc/apk/world

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

rc_add sshd default
rc_add networkmanager default

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

# ── Shell profile ─────────────────────────────────────────────────────────────
mkdir -p "$tmp"/etc/profile.d
makefile root:root 0755 "$tmp"/etc/profile.d/aliases.sh <<'EOF'
alias ls='ls --color=auto'
alias ll='ls -lav --ignore=..'
alias l='ls -lav --ignore=.?*'
alias disks='lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL'
alias parts='fdisk -l'
alias mounts='findmnt --list'
EOF

# ── TUI Partition Manager ────────────────────────────────────────────────────
mkdir -p "$tmp"/usr/local/bin
makefile root:root 0755 "$tmp"/usr/local/bin/partman <<'PARTMAN_EOF'
#!/bin/sh
# ============================================================================
# SuperLite OS — TUI Partition Manager
# CRUD operations for disk partitions
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

# ── List Disks ────────────────────────────────────────────────────────────────
list_disks() {
    header "Available Disks"
    printf "  ${BOLD}%-12s %-10s %-30s %-8s${NC}\n" "DEVICE" "SIZE" "MODEL" "TYPE"
    printf "  %s\n" "$(printf '─%.0s' $(seq 1 65))"
    lsblk -dno NAME,SIZE,MODEL,TYPE | while read -r name size model type; do
        printf "  %-12s %-10s %-30s %-8s\n" "$name" "$size" "$model" "$type"
    done
    echo ""
}

# ── Show Partition Details ────────────────────────────────────────────────────
show_partitions() {
    header "Partition Details"
    printf "  ${BOLD}%-15s %-10s %-10s %-15s %-20s${NC}\n" "PARTITION" "SIZE" "FSTYPE" "MOUNT" "LABEL"
    printf "  %s\n" "$(printf '─%.0s' $(seq 1 75))"
    lsblk -no NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL | grep -v "^loop" | while read -r name size fstype mount label; do
        printf "  %-15s %-10s %-10s %-15s %-20s\n" "$name" "$size" "${fstype:-—}" "${mount:-—}" "${label:-—}"
    done
    echo ""
}

# ── Create Partition ──────────────────────────────────────────────────────────
create_partition() {
    header "Create Partition"
    list_disks

    printf "  ${BOLD}Target disk (e.g., sda, vda, nvme0n1):${NC} "
    read -r disk
    dev="/dev/$disk"

    if [ ! -b "$dev" ]; then
        fail "Device $dev not found"
        return 1
    fi

    # Check partition table
    pttype=$(blkid -s PTTYPE -o value "$dev" 2>/dev/null || echo "none")
    info "Current partition table: $pttype"

    printf "  ${BOLD}Partition table type:${NC}\n"
    printf "    1) GPT (GUID)\n"
    printf "    2) MBR (DOS)\n"
    printf "    3) Keep existing\n"
    printf "  Choose [1-3]: "
    read -r pt_choice

    case "$pt_choice" in
        1)
            if confirm "Create GPT on $dev? (destroys all data)"; then
                parted -s "$dev" mklabel gpt
                ok "GPT created"
            fi
            ;;
        2)
            if confirm "Create MBR on $dev? (destroys all data)"; then
                parted -s "$dev" mklabel msdos
                ok "MBR created"
            fi
            ;;
        3) info "Keeping existing table" ;;
        *) fail "Invalid"; return 1 ;;
    esac

    # Get existing partitions to find free space
    info "Current partitions on $dev:"
    parted -s "$dev" print free 2>/dev/null | tail -n +3

    printf "\n  ${BOLD}Start (e.g., 1MiB, 513MiB, or 'auto'):${NC} "
    read -r start
    [ "$start" = "auto" ] && start="1MiB"

    printf "  ${BOLD}End (e.g., 10GiB, 100%% or '100%%'):${NC} "
    read -r end
    [ "$end" = "100%" ] && end="100%"

    printf "  ${BOLD}Filesystem:${NC}\n"
    printf "    1) ext4\n"
    printf "    2) ext3\n"
    printf "    3) ext2\n"
    printf "    4) FAT32\n"
    printf "    5) NTFS\n"
    printf "    6) Btrfs\n"
    printf "    7) XFS\n"
    printf "    8) F2FS\n"
    printf "    9) linux-swap\n"
    printf "   10) Leave unformatted\n"
    printf "  Choose [1-10]: "
    read -r fs_choice

    case "$fs_choice" in
        1) fs="ext4"; mkfs_cmd="mkfs.ext4 -F" ;;
        2) fs="ext3"; mkfs_cmd="mkfs.ext3 -F" ;;
        3) fs="ext2"; mkfs_cmd="mkfs.ext2 -F" ;;
        4) fs="fat32"; mkfs_cmd="mkfs.fat -F32" ;;
        5) fs="ntfs"; mkfs_cmd="mkfs.ntfs -f" ;;
        6) fs="btrfs"; mkfs_cmd="mkfs.btrfs -f" ;;
        7) fs="xfs"; mkfs_cmd="mkfs.xfs -f" ;;
        8) fs="f2fs"; mkfs_cmd="mkfs.f2fs -f" ;;
        9) fs="linux-swap"; mkfs_cmd="mkswap" ;;
        10) fs=""; mkfs_cmd="" ;;
        *) fail "Invalid"; return 1 ;;
    esac

    printf "  ${BOLD}Partition name/label (optional):${NC} "
    read -r label

    # Determine partition number
    part_num=$(parted -s "$dev" print 2>/dev/null | grep -c "^[[:space:]]*[0-9]" || echo 0)
    part_num=$((part_num + 1))

    # Create partition
    info "Creating partition $part_num on $dev..."
    if [ -n "$fs" ] && [ "$fs" != "linux-swap" ]; then
        parted -s "$dev" mkpart primary "$fs" "$start" "$end"
    else
        parted -s "$dev" mkpart primary "$start" "$end"
    fi

    # Get partition device name
    case "$dev" in
        *nvme*) part_dev="${dev}p${part_num}" ;;
        *) part_dev="${dev}${part_num}" ;;
    esac

    # Format
    if [ -n "$mkfs_cmd" ]; then
        info "Formatting $part_dev as $fs..."
        sleep 1  # wait for kernel to see partition
        $mkfs_cmd "$part_dev"
    fi

    # Set label
    if [ -n "$label" ]; then
        case "$fs" in
            ext4|ext3|ext2) e2label "$part_dev" "$label" ;;
            fat32) fatlabel "$part_dev" "$label" ;;
            btrfs) btrfs filesystem label "$part_dev" "$label" ;;
            xfs) xfs_admin -L "$label" "$part_dev" ;;
        esac
    fi

    ok "Partition $part_dev created"
    lsblk "$part_dev" 2>/dev/null || true
}

# ── Delete Partition ──────────────────────────────────────────────────────────
delete_partition() {
    header "Delete Partition"
    show_partitions

    printf "  ${BOLD}Partition to delete (e.g., sda1, nvme0n1p2):${NC} "
    read -r part
    dev="/dev/$part"

    if [ ! -b "$dev" ]; then
        fail "Partition $dev not found"
        return 1
    fi

    # Get parent disk
    parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
    if [ -z "$parent" ]; then
        fail "Cannot determine parent disk"
        return 1
    fi

    # Get partition number
    num=$(echo "$part" | grep -o '[0-9]*$')

    # Check if mounted
    if mountpoint -q "$dev" 2>/dev/null; then
        warn "Partition $dev is mounted"
        if confirm "Unmount it?"; then
            umount "$dev"
            ok "Unmounted"
        else
            fail "Cannot delete mounted partition"
            return 1
        fi
    fi

    if confirm "DELETE partition $dev? This cannot be undone!"; then
        parted -s "/dev/$parent" rm "$num"
        ok "Partition $dev deleted"
    else
        info "Cancelled"
    fi
}

# ── Resize Partition ──────────────────────────────────────────────────────────
resize_partition() {
    header "Resize Partition"
    show_partitions

    printf "  ${BOLD}Partition to resize (e.g., sda1):${NC} "
    read -r part
    dev="/dev/$part"

    if [ ! -b "$dev" ]; then
        fail "Partition $dev not found"
        return 1
    fi

    parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
    num=$(echo "$part" | grep -o '[0-9]*$')

    info "Current partition info:"
    parted -s "/dev/$parent" print 2>/dev/null | grep "^ *$num "

    printf "\n  ${BOLD}New size (e.g., 10GiB, 50%% or '100%%'):${NC} "
    read -r new_size

    if mountpoint -q "$dev" 2>/dev/null; then
        warn "Partition is mounted. Unmounting..."
        umount "$dev"
    fi

    info "Resizing $dev to $new_size..."
    parted -s "/dev/$parent" resizepart "$num" "$new_size"
    ok "Partition $dev resized"

    # Offer to resize filesystem
    fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null)
    if [ -n "$fstype" ] && confirm "Resize $fstype filesystem to fill partition?"; then
        case "$fstype" in
            ext4|ext3|ext2) resize2fs "$dev" ;;
            btrfs) btrfs filesystem resize max "$dev" 2>/dev/null || true ;;
            xfs) xfs_growfs "$dev" ;;
            f2fs) resize.f2fs "$dev" ;;
            *) warn "Auto-resize not supported for $fstype" ;;
        esac
        ok "Filesystem resized"
    fi
}

# ── Mount/Unmount ─────────────────────────────────────────────────────────────
mount_partition() {
    header "Mount Partition"

    printf "  ${BOLD}Partition (e.g., sda1):${NC} "
    read -r part
    dev="/dev/$part"

    if [ ! -b "$dev" ]; then
        fail "Partition $dev not found"
        return 1
    fi

    printf "  ${BOLD}Mount point (e.g., /mnt/data):${NC} "
    read -r mountpoint_path

    mkdir -p "$mountpoint_path"
    mount "$dev" "$mountpoint_path"
    ok "Mounted $dev at $mountpoint_path"
    df -h "$mountpoint_path"
}

umount_partition() {
    header "Unmount Partition"

    printf "  ${BOLD}Partition or mount point:${NC} "
    read -r target

    umount "$target"
    ok "Unmounted $target"
}

# ── Partition Info ────────────────────────────────────────────────────────────
partition_info() {
    header "Partition Info"

    printf "  ${BOLD}Device (e.g., sda1 or sda):${NC} "
    read -r dev
    dev="/dev/$dev"

    if [ ! -b "$dev" ]; then
        fail "Device $dev not found"
        return 1
    fi

    echo ""
    info "Block device info:"
    lsblk -f "$dev"
    echo ""

    info "Detailed info:"
    blkid "$dev"
    echo ""

    if echo "$dev" | grep -q '[0-9]$'; then
        info "Filesystem usage:"
        df -h "$dev" 2>/dev/null || true
    fi
}

# ── Wipe Disk ─────────────────────────────────────────────────────────────────
wipe_disk() {
    header "Wipe Disk"
    list_disks

    printf "  ${BOLD}Disk to wipe (e.g., sda):${NC} "
    read -r disk
    dev="/dev/$disk"

    if [ ! -b "$dev" ]; then
        fail "Device $dev not found"
        return 1
    fi

    printf "\n  ${RED}${BOLD}WARNING: This will DESTROY all data on $dev!${NC}\n"
    printf "  Type ${BOLD}YES${NC} to confirm: "
    read -r confirm
    if [ "$confirm" != "YES" ]; then
        info "Cancelled"
        return 0
    fi

    info "Wiping filesystem signatures..."
    wipefs -a "$dev"

    info "Zeroing first 1MB..."
    dd if=/dev/zero of="$dev" bs=1M count=1 2>/dev/null

    ok "Disk $dev wiped"
}

# ── Auto Partition ────────────────────────────────────────────────────────────
auto_partition() {
    header "Auto Partition (GPT: EFI + Swap + Root)"
    list_disks

    printf "  ${BOLD}Target disk (e.g., sda, nvme0n1):${NC} "
    read -r disk
    dev="/dev/$disk"

    if [ ! -b "$dev" ]; then
        fail "Device $dev not found"
        return 1
    fi

    printf "\n  ${RED}${BOLD}WARNING: This will ERASE $dev completely!${NC}\n"
    printf "  Type ${BOLD}YES${NC} to confirm: "
    read -r confirm
    if [ "$confirm" != "YES" ]; then
        info "Cancelled"
        return 0
    fi

    size_bytes=$(blockdev --getsize64 "$dev")
    size_mb=$((size_bytes / 1024 / 1024))

    # Wipe
    wipefs -a "$dev" 2>/dev/null || true

    # GPT
    parted -s "$dev" mklabel gpt
    ok "GPT label created"

    # EFI (512MB)
    parted -s "$dev" mkpart ESP fat32 1MiB 513MiB
    parted -s "$dev" set 1 esp on

    # Swap (2GB or 10%)
    swap_mb=$((size_mb / 10))
    [ "$swap_mb" -gt 2048 ] && swap_mb=2048
    swap_end=$((513 + swap_mb))
    parted -s "$dev" mkpart primary linux-swap 513MiB "${swap_end}MiB"

    # Root (rest)
    parted -s "$dev" mkpart primary ext4 "${swap_end}MiB" 100%

    # Partition device names
    case "$dev" in
        *nvme*) sep="p" ;;
        *) sep="" ;;
    esac

    info "Formatting..."
    sleep 1
    mkfs.fat -F32 "${dev}${sep}1"
    mkswap "${dev}${sep}2"
    mkfs.ext4 -F "${dev}${sep}3"

    ok "EFI:   ${dev}${sep}1 (512MB, FAT32)"
    ok "Swap:  ${dev}${sep}2 (${swap_mb}MB)"
    ok "Root:  ${dev}${sep}3 (ext4, rest of disk)"
    echo ""
    lsblk "$dev"
}

# ── Benchmark Disk ────────────────────────────────────────────────────────────
benchmark_disk() {
    header "Disk Benchmark"

    printf "  ${BOLD}Device to benchmark (e.g., sda1):${NC} "
    read -r part
    dev="/dev/$part"

    if [ ! -b "$dev" ]; then
        fail "Device $dev not found"
        return 1
    fi

    # Need to mount for write test
    tmp_mount="/tmp/bench_$$"
    mkdir -p "$tmp_mount"
    mount "$dev" "$tmp_mount" 2>/dev/null || true

    info "Sequential write test (128MB)..."
    dd if=/dev/zero of="$tmp_mount/.bench" bs=1M count=128 conv=fdatasync 2>&1 | grep -E "bytes|copied"

    info "Sequential read test (128MB)..."
    dd if="$tmp_mount/.bench" of=/dev/null bs=1M 2>&1 | grep -E "bytes|copied"

    rm -f "$tmp_mount/.bench"
    umount "$tmp_mount" 2>/dev/null
    rmdir "$tmp_mount" 2>/dev/null

    ok "Benchmark complete"
}

# ── Main Menu ─────────────────────────────────────────────────────────────────
show_menu() {
    clear
    printf "${BOLD}${CYAN}"
    printf "  ╔══════════════════════════════════════════╗\n"
    printf "  ║       SuperLite Partition Manager        ║\n"
    printf "  ║       Disk CRUD Operations               ║\n"
    printf "  ╚══════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "  ${BOLD}View:${NC}\n"
    printf "    1) List disks\n"
    printf "    2) Show partition details\n"
    printf "    3) Partition info\n"
    printf "\n"
    printf "  ${BOLD}Create / Modify:${NC}\n"
    printf "    4) Create partition\n"
    printf "    5) Delete partition\n"
    printf "    6) Resize partition\n"
    printf "    7) Auto partition (EFI + swap + root)\n"
    printf "\n"
    printf "  ${BOLD}Filesystem:${NC}\n"
    printf "    8) Mount partition\n"
    printf "    9) Unmount partition\n"
    printf "   10) Wipe disk\n"
    printf "   11) Benchmark disk\n"
    printf "\n"
    printf "  ${BOLD}Tools:${NC}\n"
    printf "   12) Launch cfdisk (interactive)\n"
    printf "   13) Launch sgdisk (interactive)\n"
    printf "   14) Open shell\n"
    printf "\n"
    printf "    0) Shutdown\n"
    printf "\n"
    printf "  Choose [0-14]: "
}

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
    show_menu
    read -r choice
    case "$choice" in
        1) list_disks; pause ;;
        2) show_partitions; pause ;;
        3) partition_info; pause ;;
        4) create_partition; pause ;;
        5) delete_partition; pause ;;
        6) resize_partition; pause ;;
        7) auto_partition; pause ;;
        8) mount_partition; pause ;;
        9) umount_partition; pause ;;
        10) wipe_disk; pause ;;
        11) benchmark_disk; pause ;;
        12) cfdisk ;;
        13) sgdisk ;;
        14) /bin/sh ;;
        0) poweroff ;;
        *) warn "Invalid choice"; sleep 1 ;;
    esac
done
PARTMAN_EOF

# ── MOTD ──────────────────────────────────────────────────────────────────────
makefile root:root 0644 "$tmp"/etc/motd <<'EOF'

        ╲╲╲╲
       ╲╲╲╲╲╲
      ╲╲    ╲╲
     ╲╲      ╲╲          superlite partition manager
    ╲╲        ╲╲         ──────────────────────────────────
   ╲╲    ╱╲    ╲╲        Alpine · Disk Tools · Terminal
  ╲╲    ╱  ╲    ╲╲
 ╲╲    ╱    ╲    ╲╲      run: partman
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
printf '  Run \033[1mpartman\033[0m to manage disk partitions.\n\n'
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
