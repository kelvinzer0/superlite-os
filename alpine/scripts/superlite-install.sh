#!/bin/sh
# ============================================================================
# SuperLite OS — Disk Installer (Hardcore Edition)
# Auto scan disk, partisi, format, install ke disk nyata
# ============================================================================

set -e

log() { echo "[install] $*"; }
err() { echo "[install] ERROR: $*" >&2; exit 1; }
confirm() {
    printf "%s [y/N]: " "$1"
    read -r ans
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ── Scan semua disk ──────────────────────────────────────────────────────────
log "Scanning disks..."
DISKS=""
for dev in /dev/sda /dev/sdb /dev/sdc /dev/nvme0n1 /dev/nvme1n1 /dev/mmcblk0 /dev/vda; do
    [ -b "$dev" ] || continue
    SIZE=$(blockdev --getsize64 "$dev" 2>/dev/null | awk '{printf "%.0f GB\n", $1/1024/1024/1024}')
    MODEL=$(cat /sys/block/$(basename "$dev")/device/model 2>/dev/null | tr -s ' ' | head -c 30 || echo "Unknown")
    log "  Found: $dev — $MODEL ($SIZE)"
    DISKS="$DISKS $dev"
done

[ -z "$DISKS" ] && err "No disks found!"

# ── Pilih disk target ────────────────────────────────────────────────────────
log "Available disks: $DISKS"
printf "Enter target disk (e.g. /dev/sda): "
read TARGET_DISK
[ -b "$TARGET_DISK" ] || err "Invalid disk: $TARGET_DISK"

SIZE=$(blockdev --getsize64 "$TARGET_DISK" 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024/1024}')
log "Target: $TARGET_DISK ($SIZE)"
confirm "WARNING: ALL DATA ON $TARGET_DISK WILL BE ERASED. Continue?" || err "Aborted."

# ── Auto Partisi ─────────────────────────────────────────────────────────────
log "Partitioning $TARGET_DISK..."

# Detect if UEFI atau BIOS
UEFI=false
[ -d /sys/firmware/efi ] && UEFI=true

if $UEFI; then
    log "UEFI mode — creating GPT partition table"
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%
    EFI_PART="${TARGET_DISK}1"
    ROOT_PART="${TARGET_DISK}2"
    # Handle nvme naming (nvme0n1p1 bukan nvme0n11)
    case "$TARGET_DISK" in
        *nvme*|*mmcblk*)
            EFI_PART="${TARGET_DISK}p1"
            ROOT_PART="${TARGET_DISK}p2"
            ;;
    esac
else
    log "BIOS mode — creating MBR partition table"
    parted -s "$TARGET_DISK" mklabel msdos
    parted -s "$TARGET_DISK" mkpart primary ext4 1MiB 100%
    parted -s "$TARGET_DISK" set 1 boot on
    ROOT_PART="${TARGET_DISK}1"
    case "$TARGET_DISK" in
        *nvme*|*mmcblk*)
            ROOT_PART="${TARGET_DISK}p1"
            ;;
    esac
fi

# ── Format ───────────────────────────────────────────────────────────────────
log "Formatting partitions..."
if $UEFI; then
    mkfs.vfat -F32 -n EFI "$EFI_PART" || err "Failed to format EFI partition"
fi
mkfs.ext4 -L superlite-root "$ROOT_PART" || err "Failed to format root partition"

# ── Mount dan Install ────────────────────────────────────────────────────────
log "Mounting target..."
INSTALL_ROOT="/mnt/superlite-install"
mkdir -p "$INSTALL_ROOT"
mount "$ROOT_PART" "$INSTALL_ROOT" || err "Failed to mount root"

if $UEFI; then
    mkdir -p "$INSTALL_ROOT/boot/efi"
    mount "$EFI_PART" "$INSTALL_ROOT/boot/efi" || err "Failed to mount EFI"
fi

# Temukan squashfs live media
SQUASH=""
for path in /media/cdrom/live/rootfs.squashfs /live/rootfs.squashfs /mnt/boot-media/live/rootfs.squashfs; do
    [ -f "$path" ] && SQUASH="$path" && break
done
[ -z "$SQUASH" ] && err "Cannot find rootfs.squashfs — are you booted in live mode?"

log "Extracting system from $SQUASH (this will take several minutes)..."
if command -v unsquashfs >/dev/null 2>&1; then
    unsquashfs -f -d "$INSTALL_ROOT" "$SQUASH" || err "unsquashfs failed"
else
    # Fallback: mount squashfs dan rsync
    SQUASH_MNT="/mnt/squash-tmp"
    mkdir -p "$SQUASH_MNT"
    mount -t squashfs -o ro "$SQUASH" "$SQUASH_MNT" || err "Cannot mount squashfs"
    cp -ax "$SQUASH_MNT/." "$INSTALL_ROOT/" || err "Copy failed"
    umount "$SQUASH_MNT"
fi

# ── Setup fstab ──────────────────────────────────────────────────────────────
log "Writing /etc/fstab..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
cat > "$INSTALL_ROOT/etc/fstab" << EOF
# SuperLite OS fstab
UUID=$ROOT_UUID  /  ext4  defaults,noatime  0 1
EOF
if $UEFI; then
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
    echo "UUID=$EFI_UUID  /boot/efi  vfat  defaults  0 2" >> "$INSTALL_ROOT/etc/fstab"
fi
echo "tmpfs  /tmp  tmpfs  defaults,nosuid,nodev  0 0" >> "$INSTALL_ROOT/etc/fstab"

# ── Install Bootloader ────────────────────────────────────────────────────────
log "Installing bootloader..."
KVER=$(ls "$INSTALL_ROOT/lib/modules/" 2>/dev/null | head -1)

if $UEFI; then
    # GRUB EFI
    mount --bind /dev  "$INSTALL_ROOT/dev"
    mount --bind /proc "$INSTALL_ROOT/proc"
    mount --bind /sys  "$INSTALL_ROOT/sys"
    chroot "$INSTALL_ROOT" grub-install --target=x86_64-efi \
        --efi-directory=/boot/efi --bootloader-id=SuperLite 2>/dev/null || \
        log "WARNING: grub-install failed (may need manual setup)"
    chroot "$INSTALL_ROOT" grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
    umount "$INSTALL_ROOT/sys" "$INSTALL_ROOT/proc" "$INSTALL_ROOT/dev" 2>/dev/null
else
    # GRUB BIOS / Syslinux
    if command -v syslinux >/dev/null 2>&1; then
        dd if=/usr/lib/syslinux/bios/mbr.bin of="$TARGET_DISK" bs=440 count=1 2>/dev/null || true
        syslinux --install "$ROOT_PART" 2>/dev/null || true
        # Tulis syslinux.cfg
        mkdir -p "$INSTALL_ROOT/boot/syslinux"
        cat > "$INSTALL_ROOT/boot/syslinux/syslinux.cfg" << SYSEOF
DEFAULT superlite
TIMEOUT 30
LABEL superlite
    LINUX /boot/vmlinuz-lts
    APPEND root=UUID=$ROOT_UUID rw quiet
    INITRD /boot/initramfs-lts
SYSEOF
    fi
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
log "Unmounting..."
$UEFI && umount "$INSTALL_ROOT/boot/efi" 2>/dev/null || true
umount "$INSTALL_ROOT" 2>/dev/null || true

log "==================================================="
log "SuperLite OS installed to $TARGET_DISK"
log "You can now reboot and remove the live media."
log "==================================================="
