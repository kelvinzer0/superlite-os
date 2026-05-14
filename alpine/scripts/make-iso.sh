#!/bin/bash
# ============================================================================
# SuperLite OS — ISO Generator
# Creates a hybrid ISO bootable via UEFI (GRUB) and Legacy BIOS (syslinux)
# Compatible with Rufus (ISO+DD mode) and Ventoy
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defaults
ROOTFS=""
ISO_DIR="${TOP_DIR}/iso"
OUTPUT="${TOP_DIR}/superlite-os.iso"
VERSION="$(date +%Y%m%d)"
NO_EFI=false
VERBOSE=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rootfs)   ROOTFS="$2"; shift 2 ;;
        --iso-dir)  ISO_DIR="$2"; shift 2 ;;
        --output)   OUTPUT="$2"; shift 2 ;;
        --version)  VERSION="$2"; shift 2 ;;
        --no-efi)   NO_EFI=true; shift ;;
        --verbose)  VERBOSE=true; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[[ -z "$ROOTFS" ]] && { echo "ERROR: --rootfs required"; exit 1; }
[[ -d "$ROOTFS" ]] || { echo "ERROR: rootfs dir not found: $ROOTFS"; exit 1; }

log() { echo "[iso] $*"; }
debug() { [[ "$VERBOSE" == true ]] && echo "[iso-debug] $*" || true; }

# ── Clean and prepare ISO directory ───────────────────────────────────────────
log "Preparing ISO directory..."
rm -rf "${ISO_DIR:?}/"*
mkdir -p "${ISO_DIR}"/{boot/{grub,syslinux},EFI/BOOT,live,superlite}

# ── Version file ──────────────────────────────────────────────────────────────
echo "${VERSION}" > "${ISO_DIR}/superlite/version.txt"
echo "SuperLite OS" >> "${ISO_DIR}/superlite/version.txt"
echo "Alpine Linux + LabWC Wayland" >> "${ISO_DIR}/superlite/version.txt"

# ── Copy kernel from rootfs ───────────────────────────────────────────────────
log "Copying kernel..."
KVER=$(ls "${ROOTFS}/boot/vmlinuz-"* 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/vmlinuz-//' || echo "lts")

if [[ -f "${ROOTFS}/boot/vmlinuz-${KVER}" ]]; then
    cp "${ROOTFS}/boot/vmlinuz-${KVER}" "${ISO_DIR}/boot/vmlinuz-lts"
else
    cp "${ROOTFS}/boot/vmlinuz" "${ISO_DIR}/boot/vmlinuz-lts" 2>/dev/null \
        || cp "${ROOTFS}/boot/vmlinuz-lts" "${ISO_DIR}/boot/vmlinuz-lts" 2>/dev/null \
        || { echo "ERROR: No kernel found in rootfs"; exit 1; }
fi

# ── Regenerate initramfs with live-boot support ───────────────────────────────
log "Checking initramfs for live-boot support..."
INITRAMFS_OK=false

# Try to regenerate initramfs inside the rootfs if mkinitfs is available
if [[ -x "${ROOTFS}/usr/bin/mkinitfs" ]] || [[ -f "${ROOTFS}/sbin/mkinitfs" ]]; then
    log "Regenerating initramfs with live-boot hooks in chroot..."
    # Mount virtual fs for chroot
    mount --bind /dev     "${ROOTFS}/dev"     2>/dev/null || true
    mount --bind /dev/pts "${ROOTFS}/dev/pts" 2>/dev/null || true
    mount --bind /proc    "${ROOTFS}/proc"    2>/dev/null || true
    mount --bind /sys     "${ROOTFS}/sys"     2>/dev/null || true

    KVER=$(ls "${ROOTFS}/lib/modules/" 2>/dev/null | head -1 || echo "lts")
    if [[ -n "$KVER" ]] && [[ -d "${ROOTFS}/lib/modules/$KVER" ]]; then
        chroot "${ROOTFS}" mkinitfs -o /boot/initramfs-lts "$KVER" 2>&1 | tail -5 || true
        if [[ -f "${ROOTFS}/boot/initramfs-lts" ]]; then
            log "Patching initramfs: ensuring busybox applets and modules..."
            IRD_DIR="/tmp/superlite-ird-patch"
            rm -rf "$IRD_DIR" && mkdir -p "$IRD_DIR"
            (cd "$IRD_DIR" && zcat "${ROOTFS}/boot/initramfs-lts" | cpio -id 2>/dev/null)

            # ── Keep Alpine's patched init (patch-init.sh adds nlplug-findfs timeout) ──
            # Do NOT replace /init with superlite-live.init — it fails in initramfs context.
            # Alpine's init + SuperLite fallback (_superlite_find_media) handles boot media.

            # ── Inject busybox.static for missing applets (cttyhack, setsid, findmnt) ──
            # Alpine's dynamic busybox may not include all applets needed in initramfs
            if [[ ! -f "$IRD_DIR/bin/busybox" ]]; then
                for bb_src in \
                    "${ROOTFS}/bin/busybox.static" \
                    "${ROOTFS}/usr/bin/busybox" \
                    "${ROOTFS}/bin/busybox"; do
                    if [[ -f "$bb_src" ]]; then
                        cp "$bb_src" "$IRD_DIR/bin/busybox"
                        chmod +x "$IRD_DIR/bin/busybox"
                        log "Copied $(basename $bb_src) as busybox to initramfs"
                        break
                    fi
                done
            fi

            if [[ -f "${ROOTFS}/bin/busybox.static" ]]; then
                cp "${ROOTFS}/bin/busybox.static" "$IRD_DIR/bin/busybox.static" 2>/dev/null || true
                chmod +x "$IRD_DIR/bin/busybox.static" 2>/dev/null || true
                for applet in cttyhack setsid findmnt; do
                    if [[ ! -e "$IRD_DIR/bin/$applet" ]]; then
                        ln -sf /bin/busybox.static "$IRD_DIR/bin/$applet"
                        log "Linked $applet → busybox.static in initramfs"
                    fi
                done
            fi

            # Create missing busybox symlinks
            if [[ -f "$IRD_DIR/bin/busybox" ]]; then
                for applet in setsid cttyhack blkid findmnt switch_root \
                              mdev mountpoint sleep mkdir ls cat mount umount \
                              modprobe grep sed awk head tail wc tr cut losetup \
                              sh ash echo test expr true false \
                              printf readlink basename dirname; do
                    [[ -e "$IRD_DIR/bin/$applet" ]] || \
                        ln -sf /bin/busybox "$IRD_DIR/bin/$applet" 2>/dev/null
                done
                # Also ensure /sbin symlinks
                for applet in switch_root mdev modprobe; do
                    [[ -e "$IRD_DIR/sbin/$applet" ]] || \
                        ln -sf /bin/busybox "$IRD_DIR/sbin/$applet" 2>/dev/null
                done
            fi

            # ── Verify critical modules are in initrd ──
            # All these must be present for live-boot to work
            KVER_IRD=$(ls "$IRD_DIR/lib/modules/" 2>/dev/null | head -1 || echo "")
            if [[ -n "$KVER_IRD" ]]; then
                for mod in squashfs loop isofs sr_mod usb-storage sd_mod nls_cp437 nls_iso8859_1; do
                    if ! find "$IRD_DIR/lib/modules/$KVER_IRD" \
                         \( -name "${mod}.ko*" -o -name "${mod//_/-}.ko*" \) 2>/dev/null | grep -q .; then
                        log "WARNING: $mod module missing in initrd — copying from rootfs..."
                        KVER_ROOT=$(ls "${ROOTFS}/lib/modules/" 2>/dev/null | head -1 || echo "")
                        if [[ -n "$KVER_ROOT" ]]; then
                            while IFS= read -r -d '' mod_file; do
                                rel_path="${mod_file#${ROOTFS}/lib/modules/$KVER_ROOT/}"
                                dest_dir="$IRD_DIR/lib/modules/$KVER_IRD/$(dirname "$rel_path")"
                                mkdir -p "$dest_dir"
                                cp "$mod_file" "$dest_dir/" 2>/dev/null && \
                                    log "  Copied $mod → $(dirname $rel_path)/"
                            done < <(find "${ROOTFS}/lib/modules/$KVER_ROOT" \
                                \( -name "${mod}.ko*" -o -name "${mod//_/-}.ko*" \) \
                                -print0 2>/dev/null)
                        fi
                    fi
                done
                # Regenerate modules.dep after all modules are copied
                if command -v depmod >/dev/null 2>&1 && [[ -n "$KVER_IRD" ]]; then
                    log "Regenerating modules.dep in initramfs..."
                    depmod -a -b "$IRD_DIR" "$KVER_IRD" 2>/dev/null || true
                fi
            fi

            # Verify /init exists and is executable
            if [[ ! -x "$IRD_DIR/init" ]]; then
                log "WARNING: /init missing in initramfs — this will cause kernel panic!"
                cat > "$IRD_DIR/init" << 'INIT_FALLBACK'
#!/bin/sh
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
echo "[superlite] Fallback init: /init was missing!"
echo "[superlite] Dropping to shell..."
exec /bin/sh
INIT_FALLBACK
                chmod +x "$IRD_DIR/init"
            fi

            # Log /init for debugging
            log "Initramfs /init: $(head -1 "$IRD_DIR/init" 2>/dev/null || echo 'EMPTY')"

            (cd "$IRD_DIR" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${ROOTFS}/boot/initramfs-lts")
            rm -rf "$IRD_DIR"
            cp "${ROOTFS}/boot/initramfs-lts" "${ISO_DIR}/boot/initramfs-lts"
            INITRAMFS_OK=true
            log "Initramfs patched (SuperLite init + busybox applets + critical modules)"
        fi
    fi

    umount "${ROOTFS}/sys"     2>/dev/null || true
    umount "${ROOTFS}/proc"    2>/dev/null || true
    umount "${ROOTFS}/dev/pts" 2>/dev/null || true
    umount "${ROOTFS}/dev"     2>/dev/null || true
fi

# Fallback: copy existing initramfs from rootfs
if [[ "$INITRAMFS_OK" != true ]]; then
    log "Using pre-built initramfs from rootfs..."
    for initrd in \
        "${ROOTFS}/boot/initramfs-lts" \
        "${ROOTFS}/boot/initramfs-${KVER}" \
        "${ROOTFS}/boot/initramfs-virt"; do
        if [[ -f "$initrd" ]]; then
            cp "$initrd" "${ISO_DIR}/boot/initramfs-lts"
            INITRAMFS_OK=true
            log "Copied initramfs: $initrd"
            break
        fi
    done
fi

# Last resort: generate minimal initramfs on build host
if [[ "$INITRAMFS_OK" != true ]]; then
    log "WARNING: No initramfs found — generating minimal one..."
    # Create a minimal initramfs with live-boot support
    INITRAMFS_DIR="/tmp/superlite-initramfs"
    rm -rf "$INITRAMFS_DIR"
    mkdir -p "$INITRAMFS_DIR"/{bin,lib,lib64,proc,sys,dev,sbin,live,mnt}

    # Copy busybox from rootfs for initramfs utilities
    if [[ -f "${ROOTFS}/bin/busybox" ]]; then
        cp "${ROOTFS}/bin/busybox" "$INITRAMFS_DIR/bin/busybox"
        # Create symlinks for common utilities (expanded for live-boot)
        for util in sh mount umount modprobe sleep mkdir ls cat switch_root \
                    mountpoint mdev setsid cttyhack blkid findmnt \
                    find grep sed awk head tail wc tr cut; do
            ln -sf /bin/busybox "$INITRAMFS_DIR/bin/$util" 2>/dev/null || true
        done
    fi

    # Copy the live-boot init (as /init — kernel's default entry point)
    if [[ -f "${SCRIPT_DIR}/alpine/hooks/superlite-live.init" ]]; then
        cp "${SCRIPT_DIR}/alpine/hooks/superlite-live.init" "$INITRAMFS_DIR/init"
        cp "${SCRIPT_DIR}/alpine/hooks/superlite-live.init" "$INITRAMFS_DIR/sbin/init"
        chmod +x "$INITRAMFS_DIR/init" "$INITRAMFS_DIR/sbin/init"
    fi

    # Create essential device nodes and directories for emergency shell
    mkdir -p "$INITRAMFS_DIR"/dev/pts "$INITRAMFS_DIR"/dev/shm "$INITRAMFS_DIR"/proc "$INITRAMFS_DIR"/sys

    # Copy kernel modules (essential ones only)
    KVER=$(ls "${ROOTFS}/lib/modules/" 2>/dev/null | head -1 || echo "lts")
    if [[ -n "$KVER" ]] && [[ -d "${ROOTFS}/lib/modules/$KVER" ]]; then
        mkdir -p "$INITRAMFS_DIR/lib/modules/$KVER"
        for mod in isofs squashfs loop overlay usb-storage sd_mod sr_mod mmc_block vfat nls_cp437 nls_iso8859_1; do
            find "${ROOTFS}/lib/modules/$KVER" -name "${mod}.ko*" -exec cp {} "$INITRAMFS_DIR/lib/modules/$KVER/" \; 2>/dev/null || true
        done
        # Copy module deps
        cp "${ROOTFS}/lib/modules/$KVER/modules.dep" "$INITRAMFS_DIR/lib/modules/$KVER/" 2>/dev/null || true
        cp "${ROOTFS}/lib/modules/$KVER/modules.alias" "$INITRAMFS_DIR/lib/modules/$KVER/" 2>/dev/null || true
    fi

    # Pack into cpio.gz
    (cd "$INITRAMFS_DIR" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${ISO_DIR}/boot/initramfs-lts")
    rm -rf "$INITRAMFS_DIR"
    log "Generated minimal initramfs with live-boot support"
fi

# ── Create squashfs of rootfs ─────────────────────────────────────────────────
log "Creating squashfs (this may take a while)..."
# Remove live dir from rootfs before squashing
mkdir -p "${ROOTFS}/live" 2>/dev/null || true
mksquashfs "${ROOTFS}" "${ISO_DIR}/live/rootfs.squashfs" \
    -comp xz -b 1M -Xbcj x86 -noappend \
    -e proc sys dev run tmp live \
    2>&1 | tail -3

SQUASH_SIZE=$(du -sh "${ISO_DIR}/live/rootfs.squashfs" | cut -f1)
log "Squashfs size: ${SQUASH_SIZE}"

# ── GRUB config (UEFI) ───────────────────────────────────────────────────────
log "Writing GRUB config..."
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

# ── Syslinux config (Legacy BIOS) ────────────────────────────────────────────
log "Writing syslinux config..."
cat > "${ISO_DIR}/boot/syslinux/isolinux.cfg" << 'SYSLINUX'
SERIAL 0 115200
CONSOLE 0

DEFAULT superlite
PROMPT 1
TIMEOUT 50

# Use simple text menu (vesamenu doesn't work over serial console)
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

# ── UEFI Boot (GRUB EFI binary) ──────────────────────────────────────────────
if [[ "$NO_EFI" != true ]]; then
    log "Building UEFI boot image..."

    # Find GRUB EFI binary — try multiple locations
    GRUB_EFI_X64=""
    for path in \
        /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
        /usr/lib/grub/x86_64-efi/grubx64.efi \
        /usr/share/grub/x86_64-efi/grubx64.efi; do
        [[ -f "$path" ]] && GRUB_EFI_X64="$path" && break
    done

    if [[ -z "$GRUB_EFI_X64" ]]; then
        log "WARNING: GRUB EFI binary not found. Trying grub-mkimage..."
        # Build GRUB EFI binary from modules
        GRUB_MODULE_DIR="/usr/lib/grub/x86_64-efi"
        if [[ -d "$GRUB_MODULE_DIR" ]]; then
            mkdir -p /tmp/grub-modules
            grub-mkimage -O x86_64-efi \
                -o "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" \
                -p "/boot/grub" \
                -d "$GRUB_MODULE_DIR" \
                iso9660 fat part_gpt part_msdos normal boot linux \
                configfile loopback chain halt reboot search \
                search_fs_uuid search_label ls gfxterm gfxterm_background \
                all_video efi_gop efi_ugop video_bochs video_cirrus \
                test 2>/dev/null \
                || log "WARNING: grub-mkimage failed"
        fi
    else
        cp "$GRUB_EFI_X64" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
    fi

    # GRUB EFI config (chains to main grub.cfg)
    cat > "${ISO_DIR}/EFI/BOOT/GRUB.CFG" << 'EFIGRUB'
search --set=root --file /boot/grub/grub.cfg
configfile /boot/grub/grub.cfg
EFIGRUB

    # Create EFI boot image (FAT12) for El Torito
    log "Creating EFI boot image..."
    EFI_IMG="/tmp/superlite-efi.img"
    dd if=/dev/zero of="$EFI_IMG" bs=1K count=4096 2>/dev/null
    mkfs.vfat -F 12 "$EFI_IMG" 2>/dev/null || mkfs.vfat "$EFI_IMG" 2>/dev/null
    mcopy -s -i "$EFI_IMG" "${ISO_DIR}/EFI" ::EFI 2>/dev/null \
        || (mkdir -p /tmp/efi-mnt && mount -o loop "$EFI_IMG" /tmp/efi-mnt \
            && cp -r "${ISO_DIR}/EFI" /tmp/efi-mnt/ && umount /tmp/efi-mnt)
    cp "$EFI_IMG" "${ISO_DIR}/EFI/BOOT/efi.img"
    rm -f "$EFI_IMG"
fi

# ── Copy syslinux BIOS boot files ─────────────────────────────────────────────
log "Installing syslinux BIOS boot files..."
# Search in rootfs first, then host system paths
for f in isolinux.bin ldlinux.c32 libutil.c32 libcom32.c32 vesamenu.c32 menu.c32; do
    src=""
    # Try rootfs paths first (Alpine package installs here)
    for search in \
        "${ROOTFS}/usr/share/syslinux/$f" \
        "${ROOTFS}/usr/lib/syslinux/$f" \
        "${ROOTFS}/usr/lib/syslinux/bios/$f" \
        "/usr/lib/syslinux/bios/$f" \
        "/usr/lib/syslinux/$f" \
        "/usr/lib/ISOLINUX/$f"; do
        [[ -f "$search" ]] && src="$search" && break
    done
    [[ -n "$src" ]] && cp "$src" "${ISO_DIR}/boot/syslinux/" 2>/dev/null || true
done

# ── Find isohdpfx.bin for hybrid MBR ─────────────────────────────────────────
ISOHDPFX=""
for path in \
    "${ROOTFS}/usr/share/syslinux/isohdpfx.bin" \
    "${ROOTFS}/usr/lib/syslinux/isohdpfx.bin" \
    /usr/lib/ISOLINUX/isohdpfx.bin \
    /usr/lib/syslinux/bios/isohdpfx.bin \
    /usr/lib/syslinux/isohdpfx.bin \
    /usr/share/syslinux/isohdpfx.bin; do
    [[ -f "$path" ]] && ISOHDPFX="$path" && break
done

# ── Build ISO with xorriso ────────────────────────────────────────────────────
log "Generating hybrid ISO..."

XORRISO_ARGS=(
    -as mkisofs
    -iso-level 3
    -full-iso9660-filenames
    -volid "SUPERLITE"
    -output "$OUTPUT"
)

# Legacy BIOS boot (syslinux/isolinux)
if [[ -f "${ISO_DIR}/boot/syslinux/isolinux.bin" ]]; then
    XORRISO_ARGS+=(
        -eltorito-boot boot/syslinux/isolinux.bin
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
        --eltorito-catalog boot/syslinux/boot.cat
    )
    # Hybrid MBR for dd-mode USB boot
    [[ -n "$ISOHDPFX" ]] && XORRISO_ARGS+=(-isohybrid-mbr "$ISOHDPFX")
fi

# UEFI boot (GRUB EFI)
if [[ "$NO_EFI" != true ]] && [[ -f "${ISO_DIR}/EFI/BOOT/efi.img" ]]; then
    XORRISO_ARGS+=(
        -eltorito-alt-boot
        -e EFI/BOOT/efi.img
        -no-emul-boot
        -isohybrid-gpt-basdat
    )
fi

XORRISO_ARGS+=("$ISO_DIR")

# Run xorriso
if command -v xorriso &>/dev/null; then
    xorriso "${XORRISO_ARGS[@]}" 2>&1 | tail -5
elif command -v mkisofs &>/dev/null; then
    # Fallback to mkisofs with compatible args
    mkisofs "${XORRISO_ARGS[@]}" 2>&1 | tail -5
else
    echo "ERROR: Neither xorriso nor mkisofs found"
    exit 1
fi

ISO_SIZE=$(du -sh "$OUTPUT" | cut -f1)
log "═══════════════════════════════════════════════"
log "ISO created: ${OUTPUT}"
log "Size: ${ISO_SIZE}"
log "Boot: UEFI (GRUB) + Legacy BIOS (syslinux)"
log "Rufus: Compatible (ISO + DD mode)"
log "Ventoy: Compatible"
log "═══════════════════════════════════════════════"
