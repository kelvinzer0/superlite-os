#!/bin/sh
# ============================================================================
# SuperLite OS — Alpine init patcher (pure shell, no Python)
# Patches Alpine's mkinitfs init to add live-boot support with:
#   - Usable emergency shell with TTY + job control
#   - Partition scanning fallback when nlplug-findfs fails
#   - Multi-filesystem detection (ext4, exFAT, NTFS, vfat, iso9660)
#   - Extra kernel modules for USB/MMC/NVMe
# ============================================================================

INIT_FILE="/usr/share/mkinitfs/initramfs-init"

if [ ! -f "$INIT_FILE" ]; then
    echo "[patch-init] ERROR: $INIT_FILE not found"
    exit 1
fi

echo "[patch-init] Patching $INIT_FILE..."
cp "$INIT_FILE" "${INIT_FILE}.bak"

# ── Patch 1: Fix recovery_shell for proper TTY ──────────────────────────────
# Write the new function to a temp file, then use awk to replace
cat > /tmp/new_recovery.sh << 'RECOVERY_EOF'
recovery_shell() {
	if [ -n "$KOPT_panic" ]; then
		exit
	fi
	echo "Launching initramfs emergency recovery shell."
	echo "$1"
	mount -t devpts devpts /dev/pts 2>/dev/null || true
	if [ -c /dev/console ]; then
		setsid cttyhack /bin/sh 2>/dev/null \
			|| setsid /bin/sh </dev/console >/dev/console 2>&1 \
			|| exec /bin/sh
	else
		export PS1='(initramfs) \w \$ '
		exec /bin/sh
	fi
}
RECOVERY_EOF

# Use awk to replace the recovery_shell function
awk '
/^recovery_shell\(\) \{/ {
    while ((getline line < "/tmp/new_recovery.sh") > 0) print line
    # Skip old function body until closing }
    while (getline > 0) { if ($0 == "}") break }
    close("/tmp/new_recovery.sh")
    next
}
{ print }
' "$INIT_FILE" > "${INIT_FILE}.tmp" && mv "${INIT_FILE}.tmp" "$INIT_FILE"
rm -f /tmp/new_recovery.sh
echo "[patch-init] Patched recovery_shell"

# ── Patch 2: Add live-boot fallback after nlplug-findfs ─────────────────────
cat > /tmp/live_fallback.txt << 'FALLBACK_EOF'

# ── SuperLite OS: Enhanced boot media detection ──────────────────────────────
if [ ! -d "$ROOT" ] || [ -z "$(ls -A $ROOT 2>/dev/null)" ]; then
    echo "[live] nlplug-findfs did not find boot media, trying manual detection..."
    if command -v mdev >/dev/null 2>&1; then
        echo "/sbin/mdev" > /proc/sys/kernel/hotplug 2>/dev/null || true
        mdev -s 2>/dev/null || true
    fi
    for mod in usb-storage sd_mod sr_mod mmc_block nvme vfat fat ext4 \
               xhci_hcd ehci_hcd ohci_hcd nls_cp437 nls_iso8859_1; do
        modprobe $mod 2>/dev/null || true
    done
    sleep 2
    mdev -s 2>/dev/null || true
    sleep 1
    _live_found=no
    _live_mount="/mnt/boot-media"
    mkdir -p "$_live_mount"
    for _dev in \
        /dev/sr0 /dev/cdrom \
        /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1 \
        /dev/sda2 /dev/sdb2 \
        /dev/mmcblk0p1 /dev/mmcblk1p1 \
        /dev/nvme0n1p1 /dev/nvme0n1p2 \
        /dev/vda1 /dev/vdb1 \
        /dev/sda /dev/sdb /dev/sdc /dev/mmcblk0 /dev/nvme0n1 /dev/vda; do
        [ -b "$_dev" ] || continue
        for _fstype in iso9660 vfat ext4 exfat ntfs; do
            if mount -t "$_fstype" -o ro "$_dev" "$_live_mount" 2>/dev/null; then
                if [ -f "$_live_mount/live/rootfs.squashfs" ] || \
                   [ -d "$_live_mount/live" ] || \
                   [ -f "$_live_mount/boot/vmlinuz-lts" ]; then
                    echo "[live] Found boot media on $_dev ($_fstype)"
                    mount --bind "$_live_mount" "$ROOT" 2>/dev/null || \
                        cp -a "$_live_mount"/. "$ROOT"/ 2>/dev/null
                    _live_found=yes
                    break 2
                fi
                umount "$_live_mount" 2>/dev/null
            fi
        done
    done
    if [ "$_live_found" = "no" ]; then
        echo "[live] Manual detection failed. Available devices:"
        ls -la /dev/sd* /dev/mmcblk* /dev/nvme* /dev/vd* /dev/sr* 2>/dev/null
        echo "[live] Hint: pass live=/dev/sdX1 on kernel cmdline"
    fi
fi
# ── End SuperLite OS patch ───────────────────────────────────────────────────
FALLBACK_EOF

# Insert fallback after the "eend $?" in the boot media section
# First soften the eend, then inject our fallback
awk '
/# locate boot media and mount it/ { in_boot=1 }
in_boot && /eend \$\?/ {
    print "eend $? 2>/dev/null || true"
    while ((getline line < "/tmp/live_fallback.txt") > 0) print line
    close("/tmp/live_fallback.txt")
    in_boot=0
    next
}
{ print }
' "$INIT_FILE" > "${INIT_FILE}.tmp" && mv "${INIT_FILE}.tmp" "$INIT_FILE"
rm -f /tmp/live_fallback.txt
echo "[patch-init] Injected live-boot fallback"

# ── Patch 3: Add extra kernel modules ────────────────────────────────────────
# Append extra modules to the existing modprobe line
sed -i '/loop squashfs simpledrm/a\    modprobe -a usb-storage sd_mod sr_mod mmc_block nvme vfat fat ext4 xhci_hcd ehci_hcd nls_cp437 nls_iso8859_1 2>/dev/null || true' "$INIT_FILE"
echo "[patch-init] Added extra kernel modules"

echo "[patch-init] Done! Backup: ${INIT_FILE}.bak | Lines: $(wc -l < "$INIT_FILE")"
