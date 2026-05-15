#!/bin/sh
# ============================================================================
# SuperLite OS — Alpine init patcher (pure shell, no Python)
# Patches Alpine's mkinitfs init to add live-boot support with:
#   - Usable emergency shell (Alpine-proven, no cttyhack dependency)
#   - Partition scanning fallback when nlplug-findfs fails
#   - Multi-filesystem detection (ext4, exFAT, NTFS, vfat, iso9660)
#   - Extra kernel modules for USB/MMC/NVMe
#
# HISTORY:
#   2026-05-14: eend() trap fix — bypass recovery_shell on nlplug-findfs fail
#   2026-05-15: TOTAL OVERHAUL — fix recovery_shell cttyhack dependency,
#               add mount error logging, ensure isofs module loaded,
#               parse alpine_dev from cmdline, increase device settle time
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

# ── Patch 1: Fix recovery_shell — Alpine-proven, no cttyhack dependency ──────
# The previous version used `setsid cttyhack /bin/sh` which fails when
# busybox.static doesn't have the cttyhack applet or symlinks break.
# Alpine's stock recovery_shell uses plain `/bin/busybox sh` — proven to work.
# We enhance it with device node setup + devpts mount for job control.
cat > /tmp/new_recovery.sh << 'RECOVERY_EOF'
recovery_shell() {
	if [ -n "$KOPT_panic" ]; then
		exit
	fi
	echo ""
	echo "============================================="
	echo "  SuperLite OS: Emergency Recovery Shell"
	echo "============================================="
	[ -n "$1" ] && echo "  $1"
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
	mount -t tmpfs tmpfs /dev/shm 2>/dev/null || true

	# Method 1: cttyhack (if available — sets controlling tty properly)
	if command -v cttyhack >/dev/null 2>&1; then
		setsid cttyhack /bin/sh -l && return
	fi
	# Method 2: Use /dev/console as controlling terminal
	if [ -c /dev/console ]; then
		setsid /bin/sh -l </dev/console >/dev/console 2>&1 && return
	fi
	# Method 3: Plain busybox shell (Alpine's proven fallback)
	# This ALWAYS works because /bin/busybox is guaranteed in initramfs
	export PS1='(initramfs) \w \$ '
	exec /bin/busybox sh -l
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
echo "[patch-init] Patched recovery_shell (Alpine-proven, no cttyhack dependency)"

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

    # Parse alpine_dev from kernel cmdline (e.g., alpine_dev=cdrom:iso9660)
    _alpine_dev=""
    _alpine_fstype=""
    for _param in $(cat /proc/cmdline 2>/dev/null); do
        case "$_param" in
            alpine_dev=*)
                _alpine_dev="${_param#alpine_dev=}"
                # Format: device:fstype (e.g., cdrom:iso9660)
                case "$_alpine_dev" in
                    *:*) _alpine_fstype="${_alpine_dev#*:}"; _alpine_dev="${_alpine_dev%%:*}" ;;
                esac
                echo "[live] Kernel cmdline: alpine_dev=${_alpine_dev} fstype=${_alpine_fstype}"
                ;;
            live=*)
                _live_dev="${_param#live=}"
                if [ -b "$_live_dev" ]; then
                    echo "[live] Kernel cmdline: live device=$_live_dev"
                fi
                ;;
        esac
    done

    # Ensure device manager is running
    if command -v mdev >/dev/null 2>&1; then
        echo "/sbin/mdev" > /proc/sys/kernel/hotplug 2>/dev/null || true
        mdev -s 2>/dev/null || true
    fi

    # Load ALL storage & filesystem modules in dependency order
    # ORDER MATTERS: isofs depends on cdrom, sr_mod depends on scsi_mod+cdrom
    echo "[live] Loading storage modules..."
    _mod_loaded=0
    _mod_failed=0
    for _mod in \
        scsi_mod usb_common usbcore \
        cdrom \
        sr_mod sd_mod mmc_block \
        loop isofs squashfs \
        usb-storage \
        nvme nvme_core \
        fat vfat msdos \
        ext4 jbd2 crc16 \
        xhci_hcd ehci_hcd ohci_hcd uhci_hcd \
        nls_cp437 nls_iso8859_1 nls_ascii; do
        _modprobe_out=$(modprobe "$_mod" 2>&1)
        _modprobe_ret=$?
        if [ $_modprobe_ret -eq 0 ]; then
            _mod_loaded=$(( _mod_loaded + 1 ))
        else
            _mod_failed=$(( _mod_failed + 1 ))
            # Log actual error for debugging (not just silent skip)
            if [ -n "$_modprobe_out" ]; then
                echo "[live]   modprobe $_mod failed: $_modprobe_out"
            fi
        fi
    done
    echo "[live] Modules: ${_mod_loaded} loaded, ${_mod_failed} skipped/missing"

    # Verify critical modules are actually loaded
    for _mod in isofs cdrom sr_mod; do
        if cat /proc/modules 2>/dev/null | grep -q "^${_mod} "; then
            echo "[live]   ✓ $_mod: loaded"
        else
            echo "[live]   ✗ $_mod: NOT loaded!"
        fi
    done

    # Give SCSI/IDE/USB controllers time to register devices
    # Give SCSI/IDE/USB controllers time to register devices
    echo "[live] Waiting for storage controllers to settle..."
    sleep 5

    # Re-run mdev to pick up newly registered devices
    mdev -s 2>/dev/null || true

    # If /dev/sr0 still doesn't exist, create it manually (major 11, minor 0)
    if [ ! -b /dev/sr0 ]; then
        echo "[live] /dev/sr0 not found — creating manually (11,0)"
        mknod -m 660 /dev/sr0 b 11 0 2>/dev/null || true
    fi

    # Wait for USB/storage controllers to enumerate devices
    _wait=0
    while [ $_wait -lt 15 ]; do
        if ls /dev/sd*[0-9] /dev/sr[0-9] /dev/mmcblk*p[0-9] /dev/nvme*n*p[0-9] /dev/vd*[0-9] 2>/dev/null | head -1 >/dev/null; then
            echo "[live] Block devices detected after ${_wait}s"
            break
        fi
        mdev -s 2>/dev/null || true
        sleep 1
        _wait=$(( _wait + 1 ))
    done

    # Final mdev scan
    mdev -s 2>/dev/null || true

    # Debug: show what block devices exist
    echo "[live] Available block devices:"
    ls -la /dev/sr* /dev/cdrom /dev/sd* /dev/vd* /dev/mmcblk* /dev/nvme* 2>/dev/null | while read _line; do
        echo "[live]   $_line"
    done

    # Check if isofs module is actually loaded (critical for CD-ROM mount)
    if ! cat /proc/modules 2>/dev/null | grep -q "^isofs "; then
        echo "[live] WARNING: isofs module NOT loaded — CD-ROM mount will fail!"
        echo "[live] Trying insmod fallback with dependency chain..."
        # isofs depends on cdrom module — load in order
        _insmod_deps="cdrom isofs"
        for _mod in $_insmod_deps; do
            if cat /proc/modules 2>/dev/null | grep -q "^${_mod} "; then
                echo "[live]   $_mod: already loaded"
                continue
            fi
            _ko_file=$(find /lib/modules -name "${_mod}.ko*" 2>/dev/null | head -1)
            if [ -z "$_ko_file" ]; then
                echo "[live]   $_mod: .ko file not found!"
                continue
            fi
            # Decompress if needed (modprobe handles this, insmod doesn't)
            case "$_ko_file" in
                *.xz)   xz -d < "$_ko_file" > /tmp/${_mod}.ko 2>/dev/null && _ko_file="/tmp/${_mod}.ko" ;;
                *.gz)   gzip -d < "$_ko_file" > /tmp/${_mod}.ko 2>/dev/null && _ko_file="/tmp/${_mod}.ko" ;;
                *.zst)  zstd -d < "$_ko_file" > /tmp/${_mod}.ko 2>/dev/null && _ko_file="/tmp/${_mod}.ko" ;;
            esac
            _insmod_out=$(insmod "$_ko_file" 2>&1)
            if [ $? -eq 0 ]; then
                echo "[live]   insmod $_mod: OK"
            else
                echo "[live]   insmod $_mod: FAILED — $_insmod_out"
            fi
            rm -f /tmp/${_mod}.ko
        done
    else
        echo "[live] isofs module: loaded"
    fi

    _live_found=no
    _live_mount="/mnt/boot-media"
    mkdir -p "$_live_mount"

    # ── Phase 1: Try CD-ROM devices first (most common for ISO boot) ──
    echo "[live] Scanning for CD-ROM..."
    for _dev in /dev/sr0 /dev/cdrom /dev/sr1; do
        [ -b "$_dev" ] || continue
        echo "[live]   Trying $_dev..."
        # Retry mount up to 5 times with increasing delays
        _mount_try=0
        while [ $_mount_try -lt 5 ]; do
            _mount_err=$(mount -t iso9660 -o ro "$_dev" "$_live_mount" 2>&1)
            _mount_ret=$?
            if [ $_mount_ret -eq 0 ]; then
                if [ -f "$_live_mount/live/rootfs.squashfs" ] || \
                   [ -d "$_live_mount/live" ]; then
                    echo "[live] ✓ Found live media on $_dev (iso9660)"
                    _live_found=yes
                    break 2
                fi
                echo "[live]   Mounted $_dev but no live media found in /live/"
                ls -la "$_live_mount/" 2>/dev/null | while read _line; do
                    echo "[live]     $_line"
                done
                umount "$_live_mount" 2>/dev/null
                break
            else
                echo "[live]   mount attempt $((_mount_try + 1))/5 failed (exit $_mount_ret): $_mount_err"
            fi
            _mount_try=$(( _mount_try + 1 ))
            [ $_mount_try -lt 5 ] && sleep 2
        done
    done

    # ── Phase 2: Try all other block devices ──
    if [ "$_live_found" = "no" ]; then
        echo "[live] CD-ROM not found, scanning all block devices..."
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
            # Use detected fstype from alpine_dev if available, else try all
            if [ -n "$_alpine_fstype" ]; then
                _fstypes="$_alpine_fstype"
            else
                _fstypes="iso9660 vfat ext4 exfat ntfs"
            fi
            for _fstype in $_fstypes; do
                _mount_err=$(mount -t "$_fstype" -o ro "$_dev" "$_live_mount" 2>&1)
                if [ $? -eq 0 ]; then
                    if [ -f "$_live_mount/live/rootfs.squashfs" ] || \
                       [ -d "$_live_mount/live" ] || \
                       [ -f "$_live_mount/boot/vmlinuz-lts" ]; then
                        echo "[live] ✓ Found live media on $_dev ($_fstype)"
                        _live_found=yes
                        break 2
                    fi
                    umount "$_live_mount" 2>/dev/null
                fi
            done
        done
    fi

    # ── Phase 3: Try alpine_dev hint from cmdline ──
    if [ "$_live_found" = "no" ] && [ -n "$_alpine_dev" ]; then
        echo "[live] Trying alpine_dev hint: $_alpine_dev"
        case "$_alpine_dev" in
            cdrom)
                for _dev in /dev/sr0 /dev/cdrom /dev/sr1; do
                    [ -b "$_dev" ] || continue
                    _mount_err=$(mount -t iso9660 -o ro "$_dev" "$_live_mount" 2>&1)
                    if [ $? -eq 0 ]; then
                        if [ -f "$_live_mount/live/rootfs.squashfs" ] || [ -d "$_live_mount/live" ]; then
                            echo "[live] ✓ Found live media via alpine_dev=cdrom on $_dev"
                            _live_found=yes
                            break
                        fi
                        umount "$_live_mount" 2>/dev/null
                    else
                        echo "[live]   alpine_dev cdrom mount failed: $_mount_err"
                    fi
                done
                ;;
            *)
                if [ -b "/dev/$_alpine_dev" ]; then
                    _fstype="${_alpine_fstype:-auto}"
                    _mount_err=$(mount -t "$_fstype" -o ro "/dev/$_alpine_dev" "$_live_mount" 2>&1)
                    if [ $? -eq 0 ]; then
                        echo "[live] ✓ Found live media via alpine_dev=$_alpine_dev"
                        _live_found=yes
                    else
                        echo "[live]   alpine_dev mount failed: $_mount_err"
                    fi
                fi
                ;;
        esac
    fi

    # ── Result ──
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
        echo "[live] ============================================="
        echo "[live]   BOOT MEDIA DETECTION FAILED"
        echo "[live] ============================================="
        echo "[live] Available block devices:"
        for _dbg in /dev/sd* /dev/mmcblk* /dev/nvme* /dev/vd* /dev/sr* /dev/cdrom; do
            [ -b "$_dbg" ] && echo "[live]   $_dbg"
        done
        echo "[live] Loaded modules:"
        cat /proc/modules 2>/dev/null | head -20 | while read _line; do
            echo "[live]   $_line"
        done
        echo "[live] Kernel cmdline:"
        cat /proc/cmdline 2>/dev/null | while read _line; do
            echo "[live]   $_line"
        done
        echo "[live] Hint: pass 'alpine_dev=cdrom:iso9660' or 'live=/dev/sr0' on kernel cmdline"
        echo "[live] ============================================="
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
    # Replace nlplug-findfs with timeout-wrapped version
    # nlplug-findfs looks for Alpine-specific files and may hang on non-Alpine layouts.
    # We wrap it with a 15s timeout so the SuperLite fallback kicks in promptly.
    print "# SuperLite: nlplug-findfs with timeout (15s max)"
    print "if command -v timeout >/dev/null 2>&1; then"
    print "    timeout 15 nlplug-findfs $plugdevopts 2>/dev/null; _nlplug_ret=$?"
    print "    [ $_nlplug_ret -eq 124 ] && echo \"[live] nlplug-findfs timed out (15s) — expected for SuperLite layout\""
    print "elif command -v nlplug-findfs >/dev/null 2>&1; then"
    print "    nlplug-findfs $plugdevopts 2>/dev/null & _nlplug_pid=$!"
    print "    ( sleep 15 && kill $_nlplug_pid 2>/dev/null ) & _nlplug_timer=$!"
    print "    wait $_nlplug_pid 2>/dev/null; _nlplug_ret=$?"
    print "    kill $_nlplug_timer 2>/dev/null; wait $_nlplug_timer 2>/dev/null"
    print "else"
    print "    _nlplug_ret=1"
    print "fi"
    # Skip the original nlplug-findfs command and its continuation lines
    while (getline nextline > 0) {
        if (nextline ~ /eend/) {
            # Replace eend $? with silent capture
            print "if [ $_nlplug_ret -eq 0 ]; then"
            print "    eend 0"
            print "else"
            print "    echo \"[live] nlplug-findfs returned $_nlplug_ret (expected — SuperLite uses custom layout)\""
            print "    eend 0  # Suppress recovery_shell — fallback handles boot media"
            print "fi"
            break
        } else if (nextline ~ /^[[:space:]]/) {
            # Skip original continuation lines (we replaced the whole command)
            continue
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
# Add after the existing "loop squashfs simpledrm" line in mkinitfs init
sed -i '/loop squashfs simpledrm/a\    modprobe -a usb-storage sd_mod sr_mod mmc_block nvme vfat fat ext4 xhci_hcd ehci_hcd nls_cp437 nls_iso8859_1 2>/dev/null || true' "$INIT_FILE"
echo "[patch-init] Added extra kernel modules"

echo "[patch-init] Done! Backup: ${INIT_FILE}.bak | Lines: $(wc -l < "$INIT_FILE")"
