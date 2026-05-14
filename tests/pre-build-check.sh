#!/bin/bash
# ============================================================================
# SuperLite OS — Pre-Build Integrity Check
# Verifies critical binaries and configs exist in rootfs BEFORE ISO build.
# Run this after setup-rootfs.sh, before make-iso.sh.
#
# Exit code: 0 = all checks passed, 1 = critical failure (block build)
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; WARNINGS=$((WARNINGS + 1)); }

ROOTFS="${1:-}"
[[ -z "$ROOTFS" || ! -d "$ROOTFS" ]] && {
    echo "Usage: $0 <rootfs-directory>"
    echo "  Checks critical binaries and configs in the rootfs before ISO build."
    exit 1
}

ERRORS=0
WARNINGS=0

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║    SuperLite OS — Pre-Build Integrity Check         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Rootfs: $ROOTFS"
echo ""

# =========================================================================
# 1. Init System — /sbin/init MUST exist and be executable
# =========================================================================
echo "── Init System ──────────────────────────────────────────"

if [[ -x "$ROOTFS/sbin/init" ]]; then
    pass "/sbin/init exists and is executable"
    INIT_TYPE=$(file "$ROOTFS/sbin/init" 2>/dev/null || echo "unknown")
    echo "       Type: $INIT_TYPE"
else
    fail "/sbin/init MISSING or not executable — system will not boot!"
fi

# Check what init actually is
if [[ -L "$ROOTFS/sbin/init" ]]; then
    INIT_TARGET=$(readlink "$ROOTFS/sbin/init")
    echo "       Symlink -> $INIT_TARGET"
    if [[ ! -x "$ROOTFS/$INIT_TARGET" ]] && [[ ! -x "$INIT_TARGET" ]]; then
        fail "Init symlink target '$INIT_TARGET' is not executable!"
    else
        pass "Init symlink target is valid"
    fi
fi

# =========================================================================
# 2. Critical Busybox Applets — needed by initramfs init script
# =========================================================================
echo ""
echo "── Critical Busybox Applets (initramfs) ─────────────────"

# These applets are called by the patched Alpine init and recovery_shell()
CRITICAL_APPLETS=(
    "cttyhack"     # recovery_shell() uses this to set controlling TTY
    "setsid"       # recovery_shell() fallback for TTY control
    "switch_root"  # initramfs -> real rootfs pivot
    "mount"        # mounting filesystems
    "umount"       # unmounting
    "modprobe"     # loading kernel modules (usb-storage, isofs, etc.)
    "mdev"         # device manager for block device detection
    "mountpoint"   # checking if media is mounted
    "blkid"        # block device identification
    "findmnt"      # mount point lookup
    "losetup"      # loop device setup
)

BUSYBOX_BIN="$ROOTFS/bin/busybox"
BUSYBOX_STATIC="$ROOTFS/bin/busybox.static"
if [[ -x "$BUSYBOX_BIN" ]] || [[ -x "$BUSYBOX_STATIC" ]]; then
    pass "busybox binary exists"

    # Get busybox applet list — check both regular and static builds
    BB_LIST=$("$BUSYBOX_BIN" --list 2>/dev/null || true)
    BB_STATIC_LIST=$("$BUSYBOX_STATIC" --list 2>/dev/null || true)

    for applet in "${CRITICAL_APPLETS[@]}"; do
        # Check regular busybox, then static, then standalone binary, then runtime
        if echo "$BB_LIST" | grep -q "^${applet}$"; then
            pass "busybox applet: $applet"
        elif echo "$BB_STATIC_LIST" | grep -q "^${applet}$"; then
            pass "busybox applet: $applet (via busybox.static)"
        elif [[ -x "$ROOTFS/bin/$applet" ]] || [[ -x "$ROOTFS/sbin/$applet" ]]; then
            pass "standalone: $applet"
        elif "$BUSYBOX_BIN" "$applet" --help &>/dev/null 2>&1; then
            pass "busybox applet (runtime): $applet"
        elif [[ -x "$BUSYBOX_STATIC" ]] && "$BUSYBOX_STATIC" "$applet" --help &>/dev/null 2>&1; then
            pass "busybox applet (busybox.static): $applet"
        else
            # These are MOST critical — others are warn
            if [[ "$applet" == "cttyhack" || "$applet" == "switch_root" ]]; then
                fail "MISSING applet: $applet — initramfs recovery shell will break!"
            else
                warn "applet not found in rootfs: $applet (may be in initramfs only)"
            fi
        fi
    done
else
    fail "busybox binary NOT FOUND at $BUSYBOX_BIN"
fi

# =========================================================================
# 3. Desktop Environment — LabWC + dependencies
# =========================================================================
echo ""
echo "── Desktop Environment (LabWC) ──────────────────────────"

DE_BINARIES=(
    "usr/bin/labwc"
    "usr/bin/foot"
    "usr/bin/waybar"
    "usr/bin/swaybg"
    "usr/bin/swayidle"
    "usr/bin/mako"
    "usr/bin/brightnessctl"
)

for binpath in "${DE_BINARIES[@]}"; do
    if [[ -x "$ROOTFS/$binpath" ]]; then
        pass "$binpath"
    else
        fail "$binpath MISSING — desktop environment incomplete!"
    fi
done

# =========================================================================
# 4. Wayland Session Dependencies
# =========================================================================
echo ""
echo "── Wayland Session Dependencies ─────────────────────────"

WAYLAND_DEPS=(
    "usr/bin/seatd"         # Seat management
    "usr/bin/dbus-daemon"   # D-Bus (required by most DE components)
)

WAYLAND_LIBS=(
    "libseat.so"            # libseat library
    "libwayland-server.so"  # Wayland server
    "libwayland-client.so"  # Wayland client
)

# Mesa/wlroots use different naming on Alpine (versioned soname)
# e.g., libwlroots-0.18.so.0, libEGL_mesa.so.0, libGLESv2_mesa.so.0
MESA_LIBS=(
    "libwlroots"            # wlroots (any version: libwlroots-0.*.so.* or libwlroots.so.*)
    "libEGL_mesa"           # Mesa EGL
    "libGLESv2_mesa"        # Mesa GLES
)

for binpath in "${WAYLAND_DEPS[@]}"; do
    if [[ -x "$ROOTFS/$binpath" ]]; then
        pass "$(basename "$binpath")"
    else
        fail "$(basename "$binpath") MISSING"
    fi
done

for libname in "${WAYLAND_LIBS[@]}"; do
    # Alpine uses versioned .so files (e.g., libwlroots.so.15, libEGL_mesa.so.22)
    # Search for any version of the library
    FOUND=$(find "$ROOTFS/usr/lib" -name "${libname}*" -type f 2>/dev/null | head -1)
    FOUND_LINK=$(find "$ROOTFS/usr/lib" -name "${libname}*" -type l 2>/dev/null | head -1)
    if [[ -n "$FOUND" || -n "$FOUND_LINK" ]]; then
        pass "$libname ($(basename "${FOUND:-$FOUND_LINK}"))"
    else
        # Check /lib as well (some distros use /lib instead of /usr/lib)
        FOUND=$(find "$ROOTFS/lib" -name "${libname}*" 2>/dev/null | head -1)
        if [[ -n "$FOUND" ]]; then
            pass "$libname ($(basename "$FOUND"))"
        else
            fail "$libname MISSING — Wayland session will not start!"
        fi
    fi
done

for libname in "${MESA_LIBS[@]}"; do
    # Alpine uses versioned .so files — search all lib paths + symlinks
    FOUND=$(find "$ROOTFS/usr/lib" "$ROOTFS/lib" -name "${libname}*" \( -type f -o -type l \) 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
        pass "$libname ($(basename "$FOUND"))"
    else
        # Mesa on Alpine may use alternative naming (libEGL.so, libGLESv2.so, etc.)
        case "$libname" in
            libEGL_mesa)
                ALT=$(find "$ROOTFS/usr/lib" "$ROOTFS/lib" -name "libEGL*" \( -type f -o -type l \) 2>/dev/null | head -1)
                if [[ -n "$ALT" ]]; then pass "$libname (via $(basename "$ALT"))"; continue; fi
                ;;
            libGLESv2_mesa)
                ALT=$(find "$ROOTFS/usr/lib" "$ROOTFS/lib" -name "libGLESv2*" \( -type f -o -type l \) 2>/dev/null | head -1)
                if [[ -n "$ALT" ]]; then pass "$libname (via $(basename "$ALT"))"; continue; fi
                ;;
        esac
        # Non-critical: may be provided by mesa-egl or mesa-gl under different names
        warn "$libname not found (Alpine may use alternative naming)"
    fi
done

# =========================================================================
# 5. Deep Dependency Check — chroot ldd on critical binaries
# =========================================================================
echo ""
echo "── Deep Dependency Check (chroot ldd) ───────────────────"

# All critical binaries that MUST have working library deps
LDD_BINARIES=(
    "usr/bin/labwc"
    "usr/bin/foot"
    "usr/bin/waybar"
    "usr/bin/swaybg"
    "usr/bin/swayidle"
    "usr/bin/mako"
    "usr/bin/brightnessctl"
    "usr/bin/seatd"
    "usr/bin/dbus-daemon"
    "usr/bin/NetworkManager"
    "usr/bin/tofi"
)

LDD_ERRORS=0

# Method: Use chroot + Alpine's ldd (musl-based) for accurate results
# This avoids cross-ABI issues with host's glibc readelf/ldd
for binpath in "${LDD_BINARIES[@]}"; do
    FULLPATH="$ROOTFS/$binpath"
    [[ -f "$FULLPATH" ]] || continue
    [[ -x "$FULLPATH" ]] || continue

    BIN_NAME=$(basename "$binpath")

    # Try Alpine's ldd inside chroot (most accurate for musl binaries)
    LDD_OUT=$(chroot "$ROOTFS" /usr/bin/ldd "/$binpath" 2>/dev/null || true)

    if [[ -z "$LDD_OUT" ]]; then
        # ldd not available or failed — try host ldd with LD_LIBRARY_PATH
        LDD_OUT=$(LD_LIBRARY_PATH="$ROOTFS/usr/lib:$ROOTFS/lib:$ROOTFS/lib64" ldd "$FULLPATH" 2>/dev/null || true)
    fi

    if echo "$LDD_OUT" | grep -q "Not found\|not found\|NEEDED"; then
        NOT_FOUND=$(echo "$LDD_OUT" | grep -i "not found" | awk '{print $1}' | tr '\n' ' ')
        if [[ -n "$NOT_FOUND" ]]; then
            fail "$BIN_NAME → missing:$NOT_FOUND"
            LDD_ERRORS=$((LDD_ERRORS + 1))
        else
            pass "$BIN_NAME → all deps satisfied"
        fi
    elif [[ -n "$LDD_OUT" ]]; then
        pass "$BIN_NAME → all deps satisfied"
    else
        # Can't determine — warn but don't fail
        warn "$BIN_NAME → could not verify deps (ldd unavailable)"
    fi
done

# Also verify key libraries have their own deps met
echo ""
echo "  Checking library-to-library dependencies..."
CHECK_LIBS=(
    "libwlroots"
    "libseat"
    "libwayland-server"
    "libwayland-client"
)

for libpat in "${CHECK_LIBS[@]}"; do
    LIB_FILE=$(find "$ROOTFS/usr/lib" "$ROOTFS/lib" -name "${libpat}*" -type f 2>/dev/null | head -1)
    [[ -z "$LIB_FILE" ]] && continue

    LIB_BASENAME=$(basename "$LIB_FILE")
    # Use chroot ldd on the library
    LDD_OUT=$(chroot "$ROOTFS" /usr/bin/ldd "/usr/lib/$LIB_BASENAME" 2>/dev/null || \
              LD_LIBRARY_PATH="$ROOTFS/usr/lib:$ROOTFS/lib" ldd "$LIB_FILE" 2>/dev/null || true)

    if echo "$LDD_OUT" | grep -qi "not found"; then
        NOT_FOUND=$(echo "$LDD_OUT" | grep -i "not found" | awk '{print $1}' | tr '\n' ' ')
        fail "$LIB_BASENAME → missing deps:$NOT_FOUND"
        LDD_ERRORS=$((LDD_ERRORS + 1))
    elif [[ -n "$LDD_OUT" ]]; then
        pass "$LIB_BASENAME → all deps satisfied"
    fi
done

if [[ $LDD_ERRORS -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}Deep check found $LDD_ERRORS binaries/libs with missing dependencies!${NC}"
fi

# =========================================================================
# 6. Kernel Modules — critical for live-boot
# =========================================================================
echo ""
echo "── Kernel Modules (live-boot) ───────────────────────────"

KVER=$(ls "$ROOTFS/lib/modules/" 2>/dev/null | head -1 || echo "")
if [[ -n "$KVER" ]]; then
    pass "Kernel version: $KVER"

    CRITICAL_MODULES=(
        "isofs"         # ISO filesystem (CD-ROM boot)
        "squashfs"      # Squashfs (live rootfs)
        "loop"          # Loop devices
        "usb-storage"   # USB drives
        "sd_mod"        # SCSI disk
        "sr_mod"        # SCSI CD-ROM
        "ext4"          # ext4 filesystem
        "vfat"          # FAT filesystem
        "nls_cp437"     # Codepage for FAT
        "cdrom"         # CD-ROM support (isofs dependency)
    )

    for mod in "${CRITICAL_MODULES[@]}"; do
        # Module names may use underscores or dashes interchangeably
        MOD_ALT="${mod//_/-}"  # Convert underscores to dashes
        if find "$ROOTFS/lib/modules/$KVER" -name "${mod}.ko*" -o -name "${MOD_ALT}.ko*" 2>/dev/null | grep -q .; then
            pass "module: $mod"
        else
            # Check if module is built-in (in Module.builtin)
            if grep -qE "${mod}|${MOD_ALT}" "$ROOTFS/lib/modules/$KVER/modules.builtin" 2>/dev/null; then
                pass "module: $mod (built-in)"
            else
                warn "module not found: $mod (may be built-in or named differently)"
            fi
        fi
    done
else
    fail "No kernel modules found in $ROOTFS/lib/modules/"
fi

# =========================================================================
# 7. User & Auth Setup
# =========================================================================
echo ""
echo "── User & Auth Setup ────────────────────────────────────"

if grep -q "^live:" "$ROOTFS/etc/passwd" 2>/dev/null; then
    pass "User 'live' exists"
else
    fail "User 'live' not found in /etc/passwd"
fi

if grep -q "^live:" "$ROOTFS/etc/shadow" 2>/dev/null; then
    pass "User 'live' has password entry"
else
    warn "User 'live' not in /etc/shadow (passwordless?)"
fi

if [[ -f "$ROOTFS/etc/sudoers.d/live" ]]; then
    pass "Sudoers config for 'live' user"
else
    warn "No sudoers config for 'live' user"
fi

# =========================================================================
# 8. Auto-Login Configuration
# =========================================================================
echo ""
echo "── Auto-Login Configuration ─────────────────────────────"

if [[ -f "$ROOTFS/etc/conf.d/agetty.tty1" ]]; then
    if grep -q "autologin" "$ROOTFS/etc/conf.d/agetty.tty1"; then
        pass "tty1 auto-login configured"
    else
        warn "tty1 agetty exists but no autologin"
    fi
else
    fail "tty1 auto-login NOT configured"
fi

if [[ -f "$ROOTFS/etc/conf.d/agetty.ttyS0" ]]; then
    if grep -q "autologin" "$ROOTFS/etc/conf.d/agetty.ttyS0"; then
        pass "ttyS0 auto-login configured (QEMU/serial)"
    else
        warn "ttyS0 agetty exists but no autologin"
    fi
else
    fail "ttyS0 auto-login NOT configured — QEMU test will hang!"
fi

# =========================================================================
# 9. LabWC Auto-Start
# =========================================================================
echo ""
echo "── LabWC Auto-Start ─────────────────────────────────────"

if [[ -f "$ROOTFS/root/.profile" ]]; then
    if grep -q "exec labwc" "$ROOTFS/root/.profile"; then
        pass "root/.profile auto-starts LabWC on tty1"
    else
        fail "root/.profile does NOT auto-start LabWC!"
    fi
else
    fail "root/.profile MISSING — no LabWC auto-start!"
fi

# =========================================================================
# 10. D-Bus & Seatd Services
# =========================================================================
echo ""
echo "── OpenRC Services ──────────────────────────────────────"

REQUIRED_SERVICES=("seatd" "dbus" "networkmanager" "agetty.ttyS0")
for svc in "${REQUIRED_SERVICES[@]}"; do
    # Check 1: init script exists in /etc/init.d/ (symlink or real file)
    INIT_SCRIPT="$ROOTFS/etc/init.d/$svc"
    if [[ -x "$INIT_SCRIPT" ]] || [[ -f "$INIT_SCRIPT" ]] || [[ -L "$INIT_SCRIPT" ]]; then
        pass "Service '$svc' init script exists"

        # Check 2: verify rc-update was called (look for runlevel symlink)
        # Note: squashfs extraction may break symlinks, so also check with find
        FOUND_RUNLEVEL=false
        if find "$ROOTFS/etc/runlevels" -name "$svc" 2>/dev/null | grep -q .; then
            FOUND_RUNLEVEL=true
        fi
        # Also check if it was enabled via openrc metadata
        if [[ -d "$ROOTFS/etc/runlevels/default" ]] && ls "$ROOTFS/etc/runlevels/default/$svc" &>/dev/null 2>&1; then
            FOUND_RUNLEVEL=true
        fi

        if [[ "$FOUND_RUNLEVEL" == true ]]; then
            pass "Service '$svc' in runlevel"
        else
            warn "Service '$svc' init script exists but not found in runlevels (may be stripped by squashfs)"
        fi
    else
        # Special case: agetty.ttyS0 is a symlink to agetty — check agetty exists
        if [[ "$svc" == "agetty.ttyS0" ]] && { [[ -x "$ROOTFS/etc/init.d/agetty" ]] || [[ -f "$ROOTFS/etc/init.d/agetty" ]]; }; then
            pass "Service '$svc' (agetty base script exists, symlink created at boot)"
        else
            fail "Service '$svc' init script MISSING — won't start at boot!"
        fi
    fi
done

# =========================================================================
# 11. Profile & Environment
# =========================================================================
echo ""
echo "── Environment & Profiles ───────────────────────────────"

if [[ -f "$ROOTFS/etc/profile.d/xdg.sh" ]]; then
    pass "XDG environment profile exists"
    if grep -q "XDG_RUNTIME_DIR" "$ROOTFS/etc/profile.d/xdg.sh"; then
        pass "  XDG_RUNTIME_DIR configured"
    else
        warn "  XDG_RUNTIME_DIR missing from profile"
    fi
else
    fail "XDG environment profile MISSING"
fi

if [[ -f "$ROOTFS/etc/profile.d/xdg.sh" ]] && grep -q "WAYLAND_DISPLAY" "$ROOTFS/root/.profile" 2>/dev/null; then
    pass "WAYLAND_DISPLAY check in root profile"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "════════════════════════════════════════════════════════"
if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}FAILED: $ERRORS critical error(s), $WARNINGS warning(s)${NC}"
    echo ""
    echo "These errors WILL cause boot/desktop failures."
    echo "Fix the issues above before building the ISO."
    echo "════════════════════════════════════════════════════════"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}PASSED with $WARNINGS warning(s)${NC}"
    echo "Warnings are non-critical but should be reviewed."
    echo "════════════════════════════════════════════════════════"
    exit 0
else
    echo -e "${GREEN}ALL CHECKS PASSED${NC}"
    echo "Rootfs is ready for ISO build."
    echo "════════════════════════════════════════════════════════"
    exit 0
fi
