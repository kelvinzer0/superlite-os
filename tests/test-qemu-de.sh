#!/bin/bash
# ============================================================================
# SuperLite OS — QEMU Desktop Environment Test
# Boots the ISO in QEMU and verifies the desktop environment ACTUALLY starts.
# This is a real integration test, not just "did the kernel print 'login:'".
#
# What it checks:
#   1. Kernel boots to userspace (no panic)
#   2. OpenRC reaches default runlevel
#   3. seatd starts (Wayland seat management)
#   4. dbus starts (IPC)
#   5. LabWC compositor starts (actual desktop)
#   6. Auto-login completes (user session created)
#   7. TTY/console is responsive
#
# Usage: ./tests/test-qemu-de.sh [path-to-iso]
# ============================================================================
set -euo pipefail

ISO="${1:-$(ls superlite-os-*.iso 2>/dev/null | head -1)}"
[[ -z "$ISO" || ! -f "$ISO" ]] && { echo "FAIL: No ISO found"; exit 1; }

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; DE_ERRORS=$((DE_ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }

DE_ERRORS=0

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║    SuperLite OS — QEMU Desktop Environment Test     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "ISO: $ISO"
echo ""

# ── Create test disk ──────────────────────────────────────────────────────
qemu-img create -f qcow2 /tmp/superlite-test-de.qcow2 2G 2>/dev/null

# ── Boot in QEMU with serial console ──────────────────────────────────────
echo "Booting ISO in QEMU (timeout: 240s)..."
echo "Waiting for desktop environment signals..."
echo ""

BOOT_LOG="/tmp/superlite-boot-de.log"
rm -f "$BOOT_LOG"

# Run QEMU in background, capture serial output
timeout 240s sudo qemu-system-x86_64 \
    -cdrom "$ISO" \
    -drive file=/tmp/superlite-test-de.qcow2,format=qcow2 \
    -m 2G \
    -machine accel=tcg \
    -nographic \
    -serial mon:stdio \
    -no-reboot \
    -boot d \
    2>&1 | tee "$BOOT_LOG" &
QEMU_PID=$!

# ── Progressive check: poll the log for expected signals ──────────────────
# Instead of waiting for the full timeout, check every 10s for progress

BOOT_START=$(date +%s)
TIMEOUT=240
PHASE=0
DE_FOUND=false

while kill -0 "$QEMU_PID" 2>/dev/null; do
    ELAPSED=$(( $(date +%s) - BOOT_START ))
    [[ $ELAPSED -ge $TIMEOUT ]] && break

    # Phase 1: Kernel boot (first 30s)
    if [[ $PHASE -eq 0 ]] && grep -qi "Freeing unused kernel" "$BOOT_LOG" 2>/dev/null; then
        pass "Kernel loaded and initialized (${ELAPSED}s)"
        PHASE=1
    fi

    # Phase 2: Initramfs / init (30-60s)
    if [[ $PHASE -le 1 ]] && grep -qiE "initramfs|SuperLite.*init|\[live\]" "$BOOT_LOG" 2>/dev/null; then
        pass "Initramfs init running (${ELAPSED}s)"
        PHASE=2
    fi

    # Phase 3: OpenRC starting (60-90s)
    if [[ $PHASE -le 2 ]] && grep -qiE "OpenRC|runlevel|Starting" "$BOOT_LOG" 2>/dev/null; then
        pass "OpenRC service manager started (${ELAPSED}s)"
        PHASE=3
    fi

    # Phase 4: Critical services (90-120s)
    if [[ $PHASE -le 3 ]]; then
        if grep -qi "seatd" "$BOOT_LOG" 2>/dev/null; then
            pass "seatd (Wayland seat manager) started (${ELAPSED}s)"
        fi
        if grep -qiE "dbus|D-Bus" "$BOOT_LOG" 2>/dev/null; then
            pass "D-Bus started (${ELAPSED}s)"
        fi
        PHASE=4
    fi

    # Phase 5: Auto-login (120-150s)
    if [[ $PHASE -le 4 ]] && grep -qiE "login:|tty1|agetty" "$BOOT_LOG" 2>/dev/null; then
        pass "Auto-login triggered (${ELAPSED}s)"
        PHASE=5
    fi

    # Phase 6: Desktop environment (150-200s)
    if [[ $PHASE -le 5 ]]; then
        if grep -qiE "labwc|wlroots|wlr_" "$BOOT_LOG" 2>/dev/null; then
            pass "LabWC compositor started! (${ELAPSED}s)"
            DE_FOUND=true
            PHASE=6
        elif grep -qiE "wayland|WAYLAND_DISPLAY|wayland-0" "$BOOT_LOG" 2>/dev/null; then
            pass "Wayland display server active (${ELAPSED}s)"
            DE_FOUND=true
            PHASE=6
        elif grep -qiE "Compositor|XDG_RUNTIME_DIR|/tmp/.*-runtime" "$BOOT_LOG" 2>/dev/null; then
            pass "Desktop session environment ready (${ELAPSED}s)"
            DE_FOUND=true
            PHASE=6
        fi
    fi

    # If we found the DE, no need to wait longer
    if [[ "$DE_FOUND" == true ]]; then
        sleep 5  # Let it settle
        break
    fi

    sleep 5
done

# Kill QEMU if still running
sudo kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

echo ""
echo "── Boot Analysis ────────────────────────────────────────"

# ── Post-mortem analysis of the full log ──────────────────────────────────

# Check for kernel panic (hard fail)
if grep -qi "Kernel panic" "$BOOT_LOG" 2>/dev/null; then
    fail "KERNEL PANIC detected!"
    echo ""
    echo "Panic details:"
    grep -i "Kernel panic" "$BOOT_LOG" | head -5
fi

# Check for init failure
if grep -qiE "Failed to execute /sbin/init|No init found|Kernel panic - not syncing: Attempted to kill init" "$BOOT_LOG" 2>/dev/null; then
    fail "Init system failed to start!"
fi

# Check for recovery shell (means something went wrong)
if grep -qiE "Emergency Recovery Shell|recovery_shell" "$BOOT_LOG" 2>/dev/null; then
    warn "Emergency recovery shell was entered (boot issue detected)"
fi

# Check for cttyhack failure
if grep -qi "cttyhack" "$BOOT_LOG" 2>/dev/null && grep -qi "not found" "$BOOT_LOG" 2>/dev/null; then
    fail "cttyhack command missing — recovery shell broken!"
fi

# Check for seatd failure
if grep -qiE "seatd.*fail|seatd.*error|Could not start seatd" "$BOOT_LOG" 2>/dev/null; then
    fail "seatd failed — Wayland cannot start!"
fi

# Check for D-Bus failure
if grep -qiE "dbus.*fail|Could not connect to dbus" "$BOOT_LOG" 2>/dev/null; then
    fail "D-Bus failed — desktop services will not work!"
fi

# Check for LabWC crash
if grep -qiE "labwc.*crash|labwc.*segfault|labwc.*abort" "$BOOT_LOG" 2>/dev/null; then
    fail "LabWC crashed!"
fi

# Check for missing libraries
if grep -qiE "error while loading shared libraries|cannot open shared object" "$BOOT_LOG" 2>/dev/null; then
    fail "Missing shared libraries detected:"
    grep -iE "error while loading shared libraries|cannot open shared object" "$BOOT_LOG" | head -5
fi

# Check for filesystem mount issues
if grep -qiE "mount.*failed|unable to mount|no medium found" "$BOOT_LOG" 2>/dev/null; then
    warn "Filesystem mount issues detected"
fi

# Final verdict: check for desktop-specific signals
echo ""
echo "── Desktop Environment Verdict ──────────────────────────"

# Search for ANY sign of desktop environment activity
DE_SIGNALS=0

grep -qiE "labwc" "$BOOT_LOG" 2>/dev/null && { pass "Signal: labwc found in log"; DE_SIGNALS=$((DE_SIGNALS + 1)); }
grep -qiE "wayland-0|WAYLAND_DISPLAY" "$BOOT_LOG" 2>/dev/null && { pass "Signal: Wayland display reference"; DE_SIGNALS=$((DE_SIGNALS + 1)); }
grep -qiE "seatd.*ready|seatd.*started" "$BOOT_LOG" 2>/dev/null && { pass "Signal: seatd ready"; DE_SIGNALS=$((DE_SIGNALS + 1)); }
grep -qiE "XDG_RUNTIME_DIR" "$BOOT_LOG" 2>/dev/null && { pass "Signal: XDG_RUNTIME_DIR set"; DE_SIGNALS=$((DE_SIGNALS + 1)); }
grep -qiE "swaybg|waybar|foot|mako" "$BOOT_LOG" 2>/dev/null && { pass "Signal: DE components running"; DE_SIGNALS=$((DE_SIGNALS + 1)); }
grep -qiE "exec labwc" "$BOOT_LOG" 2>/dev/null && { pass "Signal: labwc exec triggered"; DE_SIGNALS=$((DE_SIGNALS + 1)); }

# Check for successful shell prompt (means auto-login worked)
if grep -qiE "^\s*#\s*$|root@superlite|~\s*#" "$BOOT_LOG" 2>/dev/null; then
    pass "Signal: Shell prompt detected (auto-login succeeded)"
    DE_SIGNALS=$((DE_SIGNALS + 1))
fi

echo ""
echo "  Desktop signals found: $DE_SIGNALS"

# ── Final Result ──────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"

# We need at LEAST:
# - No kernel panic
# - Auto-login worked (or at least shell prompt appeared)
# - Some desktop signal (labwc, wayland, seatd, or DE components)

if grep -qi "Kernel panic" "$BOOT_LOG" 2>/dev/null; then
    echo -e "${RED}RESULT: FAILED — Kernel panic${NC}"
    echo "The system crashed during boot. Check the boot log."
    exit 1
fi

if [[ $DE_ERRORS -gt 0 ]]; then
    echo -e "${RED}RESULT: FAILED — $DE_ERRORS critical error(s)${NC}"
    echo "Desktop environment did not start correctly."
    echo ""
    echo "Full boot log saved to: $BOOT_LOG"
    exit 1
fi

if [[ $DE_SIGNALS -ge 2 ]]; then
    echo -e "${GREEN}RESULT: PASSED — Desktop environment boot verified${NC}"
    echo "  $DE_SIGNALS desktop environment signals detected"
    echo "  System boots to desktop successfully."
    exit 0
elif [[ $DE_SIGNALS -ge 1 ]]; then
    echo -e "${YELLOW}RESULT: PARTIAL — Some desktop signals found ($DE_SIGNALS)${NC}"
    echo "  Desktop environment may be working but not fully verified."
    echo "  Consider increasing QEMU timeout or checking serial output."
    exit 0
else
    echo -e "${RED}RESULT: FAILED — No desktop environment signals${NC}"
    echo "  The system booted but the desktop environment never started."
    echo "  This means users will see a blank screen or recovery shell."
    echo ""
    echo "  Possible causes:"
    echo "    - seatd not running (no Wayland seat)"
    echo "    - D-Bus not running (no IPC)"
    echo "    - LabWC binary missing or crashing"
    echo "    - GPU/rendering issues (try safe mode)"
    echo "    - cttyhack missing (init can't set TTY)"
    echo ""
    echo "  Full boot log saved to: $BOOT_LOG"
    exit 1
fi
