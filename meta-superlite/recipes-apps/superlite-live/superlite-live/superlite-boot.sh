#!/bin/sh
# ============================================================================
# SuperLite OS — ISO Boot Builder (Yocto-aware)
# Takes Yocto-built rootfs and creates bootable hybrid ISO
#
# Usage: superlite-boot [OPTIONS]
#   --build-dir DIR    Yocto build directory (default: ./build)
#   --output FILE      Output ISO path (default: ./superlite-os-YYYYMMDD.iso)
#   --no-efi           Skip UEFI boot support
#   --verbose          Detailed output
# ============================================================================

set -e

# ── Defaults ─────────────────────────────────────────────────────────────────
BUILD_DIR="./build"
OUTPUT=""
NO_EFI=false
VERBOSE=false
VERSION="$(date +%Y%m%d)"

# ── Parse args ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --output)    OUTPUT="$2"; shift 2 ;;
        --no-efi)    NO_EFI=true; shift ;;
        --verbose)   VERBOSE=true; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[ -z "$OUTPUT" ] && OUTPUT="./superlite-os-${VERSION}.iso"

# ── Find Yocto artifacts ───────────────────────────────────────────────────
MACHINE="superlite-x86_64"
IMG_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/${MACHINE}"
SQUASHFS=""
INITRAMFS=""
KERNEL=""

# Find latest squashfs
for f in "${IMG_DIR}/superlite-os-image-${MACHINE}.squashfs-xz" \
         "${IMG_DIR}/superlite-os-image-"*.squashfs-xz; do
    [ -f "$f" ] && SQUASHFS="$f" && break
done

# Find kernel
for f in "${IMG_DIR}/bzImage" \
         "${IMG_DIR}/bzImage-${MACHINE}.bin" \
         "${IMG_DIR}/bzImage-"*; do
    [ -f "$f" ] && KERNEL="$f" && break
done

# Find initramfs (if built)
for f in "${IMG_DIR}/initramfs-"*.cpio.gz \
         "${IMG_DIR}/superlite-os-image-${MACHINE}.cpio.gz"; do
    [ -f "$f" ] && INITRAMFS="$f" && break
done

echo "═══════════════════════════════════════════════"
echo "SuperLite OS — ISO Builder (Yocto)"
echo "═══════════════════════════════════════════════"
echo "Squashfs: ${SQUASHFS:-NOT FOUND}"
echo "Kernel:   ${KERNEL:-NOT FOUND}"
echo "Initramfs:${INITRAMFS:-NOT FOUND}"
echo "Output:   ${OUTPUT}"
echo "═══════════════════════════════════════════════"

[ -z "$SQUASHFS" ] && { echo "ERROR: No squashfs image found in ${IMG_DIR}"; exit 1; }
[ -z "$KERNEL" ] && { echo "ERROR: No kernel found in ${IMG_DIR}"; exit 1; }

# ── Prepare ISO directory ──────────────────────────────────────────────────
ISO_DIR=$(mktemp -d)
trap "rm -rf $ISO_DIR" EXIT

mkdir -p "${ISO_DIR}"/{boot/{grub,syslinux},EFI/BOOT,live,superlite}

# Version
echo "${VERSION}" > "${ISO_DIR}/superlite/version.txt"
echo "SuperLite OS" >> "${ISO_DIR}/superlite/version.txt"
echo "Yocto Build" >> "${ISO_DIR}/superlite/version.txt"

# Kernel
cp "$KERNEL" "${ISO_DIR}/boot/vmlinuz-lts"

# Squashfs
cp "$SQUASHFS" "${ISO_DIR}/live/rootfs.squashfs"

# Initramfs
if [ -n "$INITRAMFS" ]; then
    cp "$INITRAMFS" "${ISO_DIR}/boot/initramfs-lts"
else
    echo "WARNING: No initramfs found — generating minimal one..."
    INITRAMFS_DIR=$(mktemp -d)
    mkdir -p "${INITRAMFS_DIR}"/{bin,lib,lib64,proc,sys,dev,sbin,live,mnt,tmp}

    # Copy busybox from Yocto sysroot
    BUSYBOX=$(find "${BUILD_DIR}/tmp-glibc/work" -name "busybox" -path "*/package/bin/*" 2>/dev/null | head -1)
    if [ -n "$BUSYBOX" ]; then
        cp "$BUSYBOX" "${INITRAMFS_DIR}/bin/busybox"
        for util in sh mount umount modprobe sleep mkdir ls cat switch_root \
                    mountpoint mdev setsid blkid findmnt grep sed losetup; do
            ln -sf /bin/busybox "${INITRAMFS_DIR}/bin/$util" 2>/dev/null || true
        done
    fi

    # Lua for live init
    LUA=$(find "${BUILD_DIR}/tmp-glibc/work" -name "lua" -path "*/package/usr/bin/*" 2>/dev/null | head -1)
    [ -n "$LUA" ] && cp "$LUA" "${INITRAMFS_DIR}/bin/lua"

    # Pack
    (cd "${INITRAMFS_DIR}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${ISO_DIR}/boot/initramfs-lts")
    rm -rf "${INITRAMFS_DIR}"
fi

# ── GRUB config (UEFI) ─────────────────────────────────────────────────────
cat > "${ISO_DIR}/boot/grub/grub.cfg" << 'GRUBCFG'
set default=0
set timeout=5
set gfxmode=auto

insmod all_video
insmod gfxterm

terminal_output gfxterm

menuentry "SuperLite OS (Live)" {
    linux /boot/vmlinuz-lts boot=live alpine_dev=cdrom:iso9660 console=ttyS0,115200 loglevel=7
    initrd /boot/initramfs-lts
}

menuentry "SuperLite OS (Live — Safe Mode)" {
    linux /boot/vmlinuz-lts boot=live alpine_dev=cdrom:iso9660 console=ttyS0,115200 nomodeset loglevel=7
    initrd /boot/initramfs-lts
}

menuentry "SuperLite OS (Live — Console)" {
    linux /boot/vmlinuz-lts boot=live alpine_dev=cdrom:iso9660 console=ttyS0,115200 3
    initrd /boot/initramfs-lts
}
GRUBCFG

# ── Syslinux config (Legacy BIOS) ──────────────────────────────────────────
cat > "${ISO_DIR}/boot/syslinux/isolinux.cfg" << 'SYSLINUX'
SERIAL 0 115200
CONSOLE 0

DEFAULT superlite
PROMPT 1
TIMEOUT 50

MENU TITLE SuperLite OS Boot Menu
MENU COLOR title    * #FFFFFFFF *
MENU COLOR sel      * #FFFFFFFF #FF0055AA *
MENU COLOR unsel    * #FFBBBBBB #FF000000 *
MENU COLOR border   * #FFFFFFFF #FF000000 *

LABEL superlite
    MENU LABEL SuperLite OS (Live)
    LINUX /boot/vmlinuz-lts
    APPEND initrd=/boot/initramfs-lts boot=live alpine_dev=cdrom:iso9660 console=ttyS0,115200 loglevel=7

LABEL safe
    MENU LABEL SuperLite OS (Safe Mode)
    LINUX /boot/vmlinuz-lts
    APPEND initrd=/boot/initramfs-lts boot=live alpine_dev=cdrom:iso9660 console=ttyS0,115200 nomodeset loglevel=7

LABEL console
    MENU LABEL SuperLite OS (Console)
    LINUX /boot/vmlinuz-lts
    APPEND initrd=/boot/initramfs-lts boot=live alpine_dev=cdrom:iso9660 console=ttyS0,115200 3
SYSLINUX

# ── UEFI Boot ──────────────────────────────────────────────────────────────
if [ "$NO_EFI" != true ]; then
    echo "[iso] Building UEFI boot image..."

    # Find or build GRUB EFI binary
    GRUB_EFI=""
    for path in /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
                /usr/lib/grub/x86_64-efi/grubx64.efi \
                "${IMG_DIR}/grub-efi-bootx64.efi"; do
        [ -f "$path" ] && GRUB_EFI="$path" && break
    done

    if [ -n "$GRUB_EFI" ]; then
        cp "$GRUB_EFI" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
    elif command -v grub-mkimage >/dev/null 2>&1; then
        GRUB_MOD="/usr/lib/grub/x86_64-efi"
        [ -d "$GRUB_MOD" ] && \
            grub-mkimage -O x86_64-efi \
                -o "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" \
                -p "/boot/grub" -d "$GRUB_MOD" \
                iso9660 fat part_gpt part_msdos normal boot linux \
                configfile loopback chain halt reboot search \
                search_fs_uuid search_label ls gfxterm all_video \
                efi_gop efi_ugop 2>/dev/null || true
    fi

    cat > "${ISO_DIR}/EFI/BOOT/GRUB.CFG" << 'EFIGRUB'
search --set=root --file /boot/grub/grub.cfg
configfile /boot/grub/grub.cfg
EFIGRUB

    # EFI boot image for El Torito
    EFI_IMG=$(mktemp)
    dd if=/dev/zero of="$EFI_IMG" bs=1K count=4096 2>/dev/null
    mkfs.vfat -F 12 "$EFI_IMG" 2>/dev/null || mkfs.vfat "$EFI_IMG" 2>/dev/null
    mcopy -s -i "$EFI_IMG" "${ISO_DIR}/EFI" ::EFI 2>/dev/null || true
    cp "$EFI_IMG" "${ISO_DIR}/EFI/BOOT/efi.img"
    rm -f "$EFI_IMG"
fi

# ── Syslinux boot files ────────────────────────────────────────────────────
for f in isolinux.bin ldlinux.c32 libutil.c32 libcom32.c32 vesamenu.c32 menu.c32; do
    for search in /usr/lib/syslinux/bios/$f /usr/lib/syslinux/$f /usr/lib/ISOLINUX/$f /usr/share/syslinux/$f; do
        [ -f "$search" ] && cp "$search" "${ISO_DIR}/boot/syslinux/" 2>/dev/null && break
    done
done

# isohdpfx.bin for hybrid MBR
ISOHDPFX=""
for path in /usr/lib/ISOLINUX/isohdpfx.bin /usr/lib/syslinux/bios/isohdpfx.bin /usr/share/syslinux/isohdpfx.bin; do
    [ -f "$path" ] && ISOHDPFX="$path" && break
done

# ── Build ISO ──────────────────────────────────────────────────────────────
echo "[iso] Generating hybrid ISO..."

XORRISO_ARGS="-as mkisofs -iso-level 3 -full-iso9660-filenames -volid SUPERLITE -output ${OUTPUT}"

# Legacy BIOS
if [ -f "${ISO_DIR}/boot/syslinux/isolinux.bin" ]; then
    XORRISO_ARGS="$XORRISO_ARGS -eltorito-boot boot/syslinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table --eltorito-catalog boot/syslinux/boot.cat"
    [ -n "$ISOHDPFX" ] && XORRISO_ARGS="$XORRISO_ARGS -isohybrid-mbr $ISOHDPFX"
fi

# UEFI
if [ "$NO_EFI" != true ] && [ -f "${ISO_DIR}/EFI/BOOT/efi.img" ]; then
    XORRISO_ARGS="$XORRISO_ARGS -eltorito-alt-boot -e EFI/BOOT/efi.img -no-emul-boot -isohybrid-gpt-basdat"
fi

xorriso $XORRISO_ARGS "${ISO_DIR}" 2>&1 | tail -5

ISO_SIZE=$(du -sh "$OUTPUT" | cut -f1)
echo "═══════════════════════════════════════════════"
echo "ISO created: ${OUTPUT}"
echo "Size: ${ISO_SIZE}"
echo "Boot: UEFI (GRUB) + Legacy BIOS (syslinux)"
echo "═══════════════════════════════════════════════"
