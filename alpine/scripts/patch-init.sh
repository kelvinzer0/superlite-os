#!/bin/sh
# ============================================================================
# SuperLite OS — Alpine init patcher (pure shell, no Python)
# Patches Alpine's mkinitfs init to add live-boot support with:
#   - Usable emergency shell with TTY + job control
#   - Partition scanning fallback when nlplug-findfs fails
#   - Multi-filesystem detection (ext4, exFAT, NTFS, vfat, iso9660)
#   - Extra kernel modules for USB/MMC/NVMe
#
# FIX (2026-05-14): eend() internally calls recovery_shell() which exec's
# into /bin/sh, so "eend $? 2>/dev/null || true" never reaches the fallback.
# Now we bypass eend entirely and capture nlplug-findfs exit code directly.
# ============================================================================

INIT_FILE="/usr/share/mkinitfs/initramfs-init"

if [ ! -f "$INIT_FILE" ]; then
    echo "[patch-init] ERROR: $INIT_FILE not found"
    exit 1
fi

# Guard: skip if already patched
if grep -q "SuperLite OS" "$INIT_FILE" 2>/dev/null; then
    echo "[patch-init] Already patched — skipping"
    exit 0
fi

echo "[patch-init] Patching $INIT_FILE..."
cp "$INIT_FILE" "${INIT_FILE}.bak"

# ── Patch 1: Fix recovery_shell for proper TTY + job control ────────────────
cat > /tmp/new_recovery.sh << 'RECOVERY_EOF'
recovery_shell() {
	if [ -n "$KOPT_panic" ]; then
		exit
	fi
	echo ""
	echo "============================================="
	echo "  SuperLite OS: Emergency Recovery Shell"
	echo "============================================="
	echo "  $1"
	echo "  Type 'exit' to reboot."
	echo "============================================="
	echo ""

	# Ensure device nodes exist (devtmpfs should be mounted by now)
	[ -c /dev/null ]    || mknod -m 666 /dev/null c 1 3 2>/dev/null || true
	[ -c /dev/console ] || mknod -m 620 /dev/console c 5 1 2>/dev/null || true
	[ -c /dev/tty ]     || mknod -m 666 /dev/tty c 5 0 2>/dev/null || true
	[ -c /dev/ptmx ]    || mknod -m 666 /dev/ptmx c 5 2 2>/dev/null || true

	# Mount devpts for proper TTY/PTY support
	mkdir -p /dev/pts /dev/shm 2>/dev/null
	mount -t devpts -o gid=5,mode=0620 devpts /dev/pts 2>/dev/null || true

	# Try to start a shell with proper controlling terminal
	# Method 1: cttyhack (busybox applet — sets controlling tty)
	if command -v cttyhack >/dev/null 2>&1; then
		setsid cttyhack /bin/sh -l && return
	fi
	# Method 2: Open /dev/console as controlling terminal
	if [ -c /dev/console ]; then
		setsid /bin/sh -l </dev/console >/dev/console 2>&1 && return
	fi
	# Method 3: Plain shell (last resort)
	export PS1='(initramfs) \w \$ '
	exec /bin/sh -l
}
RECOVERY_EOF

awk '
/^recovery_shell\(\) \{/ {
    while ((getline line < "/tmp/new_recovery.sh") > 0) print line
    while (getline > 0) { if ($0 == "}") break }
    close("/tmp/new_recovery.sh")
    next
}
{ print }
' "$INIT_FILE" > "${INIT_FILE}.tmp" && mv "${INIT_FILE}.tmp" "$INIT_FILE"
rm -f /tmp/new_recovery.sh
echo "[patch-init] Patched recovery_shell"

# ── Patch 2: Replace eend + add live-boot fallback ──────────────────────────
# THE CRITICAL FIX: Alpine's eend() calls recovery_shell() on failure, and
# recovery_shell() uses exec which REPLACES the init process. So
# "eend $? 2>/dev/null || true" never works — the fallback is never reached.
#
# Solution: Replace "eend $?" with a silent variable capture, then add
# the SuperLite fallback detection.
cat > /tmp/live_fallback.txt << 'FALLBACK_EOF'

# ── SuperLite OS: Enhanced boot media detection ──────────────────────────────
# nlplug-findfs looks for Alpine-specific files (.alpine-release, apkovl).
# SuperLite uses /live/rootfs.squashfs, so nlplug-findfs won't find it.
# This fallback scans all block devices for the SuperLite live media.
_superlite_find_media() {
    echo "[live] Boot media not found by nlplug-findfs, starting manual scan..."

    # Ensure device manager is running
    if command -v mdev >/dev/null 2>&1; then
        echo "/sbin/mdev" > /proc/sys/kernel/hotplug 2>/dev/null || true
        mdev -s 2>/dev/null || true
    fi

    # Load all storage & filesystem modules (some may already be loaded)
    for mod in \
        loop isofs \
        usb-storage sd_mod sr_mod mmc_block \
        nvme vfat fat msdos ext4 \
        xhci_hcd ehci_hcd ohci_hcd uhci_hcd \
        nls_cp437 nls_iso8859_1 nls_ascii \
        scsi_mod usb_common cdrom; do
        modprobe "$mod" 2>/dev/null || true
    done

    # Wait for USB/storage controllers to enumerate devices
    _wait=0
    while [ $_wait -lt 8 ]; do
        if ls /dev/sd*[0-9] /dev/sr[0-9] /dev/mmcblk*p[0-9] /dev/nvme*n*p[0-9] /dev/vd*[0-9] 2>/dev/null | head -1 >/dev/null; then
            break
        fi
        mdev -s 2>/dev/null || true
        sleep 1
        _wait=$(( _wait + 1 ))
    done
    [ $_wait -gt 0 ] && echo "[live] Waited ${_wait}s for devices"

    # Re-scan after modules loaded + devices settled
    mdev -s 2>/dev/null || true

    _live_found=no
    _live_mount="/mnt/boot-media"
    mkdir -p "$_live_mount"

    # Try CD-ROM devices first (most common for ISO boot)
    for _dev in /dev/sr0 /dev/cdrom /dev/sr1; do
        [ -b "$_dev" ] || continue
        if mount -t iso9660 -o ro "$_dev" "$_live_mount" 2>/dev/null; then
            if [ -f "$_live_mount/live/rootfs.squashfs" ] || \
               [ -d "$_live_mount/live" ]; then
                echo "[live] Found live media on $_dev (iso9660)"
                _live_found=yes
                break
            fi
            umount "$_live_mount" 2>/dev/null
        fi
    done

    # Then try partitions (for dd'd ISOs on USB, the raw device is iso9660)
    if [ "$_live_found" = "no" ]; then
        for _dev in \
            /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/sde1 \
            /dev/sda2 /dev/sdb2 \
            /dev/mmcblk0p1 /dev/mmcblk1p1 \
            /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/nvme1n1p1 \
            /dev/vda1 /dev/vdb1 \
            /dev/sda /dev/sdb /dev/sdc /dev/sdd \
            /dev/mmcblk0 /dev/mmcblk1 \
            /dev/nvme0n1 /dev/nvme1n1 \
            /dev/vda /dev/vdb; do
            [ -b "$_dev" ] || continue
            for _fstype in iso9660 vfat ext4 exfat ntfs; do
                if mount -t "$_fstype" -o ro "$_dev" "$_live_mount" 2>/dev/null; then
                    if [ -f "$_live_mount/live/rootfs.squashfs" ] || \
                       [ -d "$_live_mount/live" ] || \
                       [ -f "$_live_mount/boot/vmlinuz-lts" ]; then
                        echo "[live] Found live media on $_dev ($_fstype)"
                        _live_found=yes
                        break 2
                    fi
                    umount "$_live_mount" 2>/dev/null
                fi
            done
        done
    fi

    if [ "$_live_found" = "yes" ]; then
        # Bind mount the found media to $ROOT (or a new path)
        if [ -z "$ROOT" ]; then
            ROOT="/media/cdrom"
            mkdir -p "$ROOT"
        fi
        if ! mountpoint -q "$ROOT" 2>/dev/null; then
            mount --bind "$_live_mount" "$ROOT" 2>/dev/null || \
                cp -a "$_live_mount"/. "$ROOT"/ 2>/dev/null
        fi
        echo "[live] Boot media mounted at $ROOT"
        return 0
    else
        echo "[live] Manual detection FAILED. Available block devices:"
        for _dbg in /dev/sd* /dev/mmcblk* /dev/nvme* /dev/vd* /dev/sr* /dev/cdrom; do
            [ -b "$_dbg" ] && echo "[live]   $_dbg"
        done
        echo "[live] Hint: pass 'live=/dev/sdX1' on kernel cmdline"
        return 1
    fi
}

# Run the fallback if nlplug-findfs didn't find anything
if [ $_nlplug_ret -ne 0 ] || [ ! -d "$ROOT" ] || { [ -n "$ROOT" ] && [ -z "$(ls -A "$ROOT" 2>/dev/null)" ]; }; then
    _superlite_find_media
fi
# ── End SuperLite OS patch ───────────────────────────────────────────────────
FALLBACK_EOF

# Replace the entire boot media block: ebegin...nlplug-findfs...eend
# with: silent capture + fallback
awk '
/# locate boot media and mount it/ { in_boot=1 }
in_boot && /^ebegin "Mounting boot media"/ {
    print "# SuperLite: Mount boot media (silent — no recovery_shell trap)"
    print "ebegin \"Mounting boot media\""
    next
}
in_boot && /nlplug-findfs/ {
    # Print the nlplug-findfs command but capture return code
    print
    # Skip continuation lines of the nlplug-findfs command
    while (getline nextline > 0) {
        if (nextline ~ /eend/) {
            # Replace eend $? with silent capture
            print "_nlplug_ret=$?"
            print "if [ $_nlplug_ret -eq 0 ]; then"
            print "    eend 0"
            print "else"
            print "    echo \"[live] nlplug-findfs returned $_nlplug_ret (expected — SuperLite uses custom layout)\""
            print "    eend 0  # Suppress recovery_shell — fallback handles boot media"
            print "fi"
            break
        } else if (nextline ~ /^[[:space:]]/) {
            # Continuation of nlplug-findfs command
            print nextline
        } else {
            # Not part of nlplug-findfs, print and break
            print nextline
            break
        }
    }
    while ((getline line < "/tmp/live_fallback.txt") > 0) print line
    close("/tmp/live_fallback.txt")
    in_boot=0
    next
}
{ print }
' "$INIT_FILE" > "${INIT_FILE}.tmp" && mv "${INIT_FILE}.tmp" "$INIT_FILE"
rm -f /tmp/live_fallback.txt
echo "[patch-init] Injected live-boot fallback (fixed: bypasses eend trap)"

# ── Patch 3: Add extra kernel modules ────────────────────────────────────────
sed -i '/loop squashfs simpledrm/a\    modprobe -a usb-storage sd_mod sr_mod mmc_block nvme vfat fat ext4 xhci_hcd ehci_hcd nls_cp437 nls_iso8859_1 2>/dev/null || true' "$INIT_FILE"
echo "[patch-init] Added extra kernel modules"

echo "[patch-init] Done! Backup: ${INIT_FILE}.bak | Lines: $(wc -l < "$INIT_FILE")"
