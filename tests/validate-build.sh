#!/bin/bash
# ============================================================================
# SuperLite OS — Build Validation (no QEMU required)
# Tests the entire build output: ISO structure, initramfs, Lua init, modules
# Usage: ./tests/validate-build.sh [path-to-iso]
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ISO="${1:-$(ls -t "$TOP_DIR"/superlite-os-*.iso 2>/dev/null | head -1)}"
PASS=0
FAIL=0
WARN=0

green()  { echo -e "\033[0;32m✓\033[0m $*"; }
red()    { echo -e "\033[0;31m✗\033[0m $*"; }
yellow() { echo -e "\033[1;33m!\033[0m $*"; }

pass() { green "$1"; PASS=$((PASS + 1)); }
fail() { red "$1";   FAIL=$((FAIL + 1)); }
warn() { yellow "$1"; WARN=$((WARN + 1)); }

cleanup() {
    umount "$ISO_MNT" 2>/dev/null || true
    umount "$SQUASH_MNT" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ── Validate args ────────────────────────────────────────────────────────────
if [[ -z "$ISO" ]] || [[ ! -f "$ISO" ]]; then
    echo "Usage: $0 [path-to-iso]"
    echo "No ISO found. Run 'make build' first."
    exit 1
fi

echo "╔══════════════════════════════════════════════╗"
echo "║     SuperLite OS — Build Validation          ║"
echo "║     (no QEMU required)                       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "ISO: $ISO ($(du -sh "$ISO" | cut -f1))"
echo ""

WORK_DIR="/tmp/superlite-validate-$$"
ISO_MNT="$WORK_DIR/iso"
SQUASH_MNT="$WORK_DIR/squash"
mkdir -p "$ISO_MNT" "$SQUASH_MNT"

# ═══════════════════════════════════════════════════════════════════════════
# 1. ISO Structure
# ═══════════════════════════════════════════════════════════════════════════
echo "── 1. ISO Structure ──"

mount -o loop,ro "$ISO" "$ISO_MNT" 2>/dev/null \
    || { fail "Cannot mount ISO"; exit 1; }

# Required files
for f in \
    boot/vmlinuz-lts \
    boot/initramfs-lts \
    live/rootfs.squashfs \
    boot/grub/grub.cfg \
    boot/syslinux/isolinux.cfg \
    EFI/BOOT/BOOTX64.EFI \
    EFI/BOOT/GRUB.CFG; do
    if [[ -f "$ISO_MNT/$f" ]]; then
        pass "ISO: $f exists ($(du -sh "$ISO_MNT/$f" | cut -f1))"
    else
        fail "ISO: $f MISSING"
    fi
done

# Kernel size check
KSIZE=$(stat -c%s "$ISO_MNT/boot/vmlinuz-lts" 2>/dev/null || echo 0)
if [[ "$KSIZE" -gt 1000000 ]]; then
    pass "ISO: kernel size OK ($(numfmt --to=iec "$KSIZE"))"
else
    fail "ISO: kernel too small ($KSIZE bytes) — likely corrupt"
fi

# Initramfs size check
ISIZE=$(stat -c%s "$ISO_MNT/boot/initramfs-lts" 2>/dev/null || echo 0)
if [[ "$ISIZE" -gt 100000 ]]; then
    pass "ISO: initramfs size OK ($(numfmt --to=iec "$ISIZE"))"
else
    fail "ISO: initramfs too small ($ISIZE bytes)"
fi

# Squashfs size check
SSIZE=$(stat -c%s "$ISO_MNT/live/rootfs.squashfs" 2>/dev/null || echo 0)
if [[ "$SSIZE" -gt 10000000 ]]; then
    pass "ISO: squashfs size OK ($(numfmt --to=iec "$SSIZE"))"
else
    fail "ISO: squashfs too small ($SSIZE bytes)"
fi

# GRUB config has correct kernel/initrd paths
if grep -q "vmlinuz-lts" "$ISO_MNT/boot/grub/grub.cfg" && \
   grep -q "initramfs-lts" "$ISO_MNT/boot/grub/grub.cfg"; then
    pass "ISO: GRUB config references correct kernel/initrd"
else
    fail "ISO: GRUB config has wrong kernel/initrd paths"
fi

# Syslinux config
if grep -q "vmlinuz-lts" "$ISO_MNT/boot/syslinux/isolinux.cfg"; then
    pass "ISO: syslinux config references correct kernel"
else
    fail "ISO: syslinux config has wrong kernel path"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# 2. Initramfs Analysis
# ═══════════════════════════════════════════════════════════════════════════
echo "── 2. Initramfs Analysis ──"

IRD_DIR="$WORK_DIR/initramfs"
mkdir -p "$IRD_DIR"
(cd "$IRD_DIR" && zcat "$ISO_MNT/boot/initramfs-lts" | cpio -id 2>/dev/null) \
    || { fail "Cannot extract initramfs"; }

# /init exists and is executable
if [[ -x "$IRD_DIR/init" ]]; then
    INIT_TYPE=$(head -1 "$IRD_DIR/init")
    pass "Initramfs: /init exists ($INIT_TYPE)"
else
    fail "Initramfs: /init MISSING or not executable — kernel panic at boot!"
fi

# /init is Lua (not shell)
if head -1 "$IRD_DIR/init" | grep -q "lua"; then
    pass "Initramfs: /init is Lua-based live-boot init"
else
    warn "Initramfs: /init is NOT Lua — may be Alpine's default (could cause blackscreen)"
fi

# Lua binary present
if [[ -f "$IRD_DIR/bin/lua" ]] && [[ -x "$IRD_DIR/bin/lua" ]]; then
    pass "Initramfs: Lua interpreter present"
else
    fail "Initramfs: Lua interpreter MISSING — Lua init cannot run"
fi

# Critical busybox applets
for applet in sh mount umount modprobe switch_root mdev mountpoint blkid findmnt losetup; do
    if [[ -e "$IRD_DIR/bin/$applet" ]] || [[ -e "$IRD_DIR/sbin/$applet" ]]; then
        pass "Initramfs: $applet available"
    else
        fail "Initramfs: $applet MISSING"
    fi
done

# Kernel modules present
KVER_IRD=$(ls "$IRD_DIR/lib/modules/" 2>/dev/null | head -1 || echo "")
if [[ -n "$KVER_IRD" ]]; then
    MOD_COUNT=$(find "$IRD_DIR/lib/modules/$KVER_IRD" -name "*.ko*" 2>/dev/null | wc -l)
    if [[ "$MOD_COUNT" -gt 0 ]]; then
        pass "Initramfs: $MOD_COUNT kernel modules present ($KVER_IRD)"
    else
        fail "Initramfs: NO kernel modules — modprobe will fail"
    fi
else
    fail "Initramfs: /lib/modules/ MISSING"
fi

# Critical modules check
if [[ -n "$KVER_IRD" ]]; then
    for mod in isofs squashfs loop sr_mod usb-storage sd_mod cdrom; do
        if find "$IRD_DIR/lib/modules/$KVER_IRD" \
             \( -name "${mod}.ko*" -o -name "${mod//_/-}.ko*" \) 2>/dev/null | grep -q .; then
            pass "Initramfs: module $mod present"
        else
            fail "Initramfs: module $mod MISSING — boot media detection will fail"
        fi
    done
fi

# Device nodes
for dev in null console tty; do
    if [[ -e "$IRD_DIR/dev/$dev" ]]; then
        pass "Initramfs: /dev/$dev exists"
    else
        warn "Initramfs: /dev/$dev missing (may be created at runtime)"
    fi
done

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# 3. Lua Init Syntax Check
# ═══════════════════════════════════════════════════════════════════════════
echo "── 3. Lua Init Validation ──"

# Syntax check with luac or lua
LUA_BIN=""
for candidate in luac lua lua5.4 lua5.3; do
    if command -v "$candidate" &>/dev/null; then
        LUA_BIN="$candidate"
        break
    fi
done

LUA_INIT="$TOP_DIR/alpine/hooks/superlite-live.init"
if [[ -f "$LUA_INIT" ]]; then
    if [[ -n "$LUA_BIN" ]]; then
        if [[ "$LUA_BIN" == "luac" ]]; then
            if luac -p "$LUA_INIT" 2>/dev/null; then
                pass "Lua init: syntax OK (luac -p)"
            else
                fail "Lua init: SYNTAX ERROR"
            fi
        else
            if "$LUA_BIN" -e "loadfile('$LUA_INIT')" 2>/dev/null; then
                pass "Lua init: syntax OK ($LUA_BIN loadfile)"
            else
                fail "Lua init: SYNTAX ERROR"
            fi
        fi
    else
        warn "Lua init: no Lua interpreter on host — skipping syntax check"
    fi

    # Check critical functions exist
    for func in mount find_boot_media emergency_shell switch_root; do
        if grep -q "function.*$func\|$func.*=.*function" "$LUA_INIT"; then
            pass "Lua init: function '$func' defined"
        else
            fail "Lua init: function '$func' MISSING"
        fi
    done

    # Check critical paths
    for path in "/mnt/iso" "/squashfs" "/live/merged" "/live/upper" "/live/work"; do
        if grep -q "$path" "$LUA_INIT"; then
            pass "Lua init: path '$path' referenced"
        else
            warn "Lua init: path '$path' not found (may be OK)"
        fi
    done
else
    fail "Lua init: $LUA_INIT not found"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# 4. Squashfs Rootfs Analysis
# ═══════════════════════════════════════════════════════════════════════════
echo "── 4. Squashfs Rootfs ──"

unsquashfs -f -d "$SQUASH_MNT" "$ISO_MNT/live/rootfs.squashfs" 2>/dev/null \
    || { fail "Cannot extract squashfs"; echo ""; continue_check=true; }

# Critical binaries
for bin in /sbin/init /bin/sh /bin/busybox; do
    if [[ -x "$SQUASH_MNT$bin" ]]; then
        pass "Squashfs: $bin executable"
    else
        fail "Squashfs: $bin MISSING — switch_root will fail"
    fi
done

# OpenRC / init system
if [[ -x "$SQUASH_MNT/sbin/openrc" ]] || [[ -x "$SQUASH_MNT/sbin/openrc-init" ]]; then
    pass "Squashfs: OpenRC init system present"
else
    fail "Squashfs: OpenRC MISSING — system cannot boot"
fi

# Desktop environment
for bin in labwc foot waybar; do
    if [[ -x "$SQUASH_MNT/usr/bin/$bin" ]]; then
        pass "Squashfs: $bin present"
    else
        warn "Squashfs: $bin missing (desktop may not start)"
    fi
done

# LabWC config
if [[ -d "$SQUASH_MNT/root/.config/labwc" ]] || [[ -d "$SQUASH_MNT/etc/skel/.config/labwc" ]]; then
    pass "Squashfs: LabWC config present"
else
    warn "Squashfs: LabWC config missing"
fi

# NetworkManager
if [[ -x "$SQUASH_MNT/usr/bin/nmcli" ]] || [[ -x "$SQUASH_MNT/usr/sbin/NetworkManager" ]]; then
    pass "Squashfs: NetworkManager present"
else
    warn "Squashfs: NetworkManager missing"
fi

# Auto-login configured
if grep -r "autologin" "$SQUASH_MNT/etc/conf.d/" 2>/dev/null | grep -q "root"; then
    pass "Squashfs: auto-login configured"
else
    warn "Squashfs: auto-login not found"
fi

# User 'live' exists
if grep -q "^live:" "$SQUASH_MNT/etc/passwd" 2>/dev/null; then
    pass "Squashfs: user 'live' exists"
else
    warn "Squashfs: user 'live' not created"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# 5. Boot Config Consistency
# ═══════════════════════════════════════════════════════════════════════════
echo "── 5. Boot Config Consistency ──"

# GRUB and syslinux use same kernel params
GRUB_CMDLINE=$(grep "linux.*vmlinuz" "$ISO_MNT/boot/grub/grub.cfg" | head -1 | sed 's/.*vmlinuz-lts //')
SYSLINUX_CMDLINE=$(grep "APPEND" "$ISO_MNT/boot/syslinux/isolinux.cfg" | head -1 | sed 's/.*initrd=[^ ]* //')

if echo "$GRUB_CMDLINE" | grep -q "boot=live" && echo "$SYSLINUX_CMDLINE" | grep -q "boot=live"; then
    pass "Boot: both GRUB and syslinux have 'boot=live'"
else
    fail "Boot: missing 'boot=live' in kernel cmdline"
fi

if echo "$GRUB_CMDLINE" | grep -q "alpine_dev="; then
    pass "Boot: GRUB has alpine_dev= parameter"
else
    warn "Boot: GRUB missing alpine_dev= (Lua init has fallback)"
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════"
echo "  PASSED:  $PASS"
echo "  FAILED:  $FAIL"
echo "  WARNINGS: $WARN"
echo "═══════════════════════════════════════════════"

if [[ "$FAIL" -eq 0 ]]; then
    green "Build validation PASSED — ISO should boot"
    exit 0
else
    red "Build validation FAILED — $FAIL issue(s) found"
    exit 1
fi
