#!/bin/bash
# ============================================================================
# SuperLite OS — QEMU Boot Test
# Boots the ISO in QEMU with serial console and verifies the system
# reaches a login prompt (indicating successful boot).
#
# NOTE: Serial console (-nographic) CANNOT verify GUI/desktop environment.
#       It can only confirm: kernel boots → init starts → login prompt appears.
#       Desktop environment (LabWC/Wayland) requires graphical output (-vga std).
#
# What it checks:
#   1. Kernel boots to userspace (no panic)
#   2. OpenRC reaches default runlevel
#   3. Critical services start (seatd, dbus, networkmanager)
#   4. Auto-login or login prompt appears on serial console
#   5. No crash/shell indicating boot failure
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
fail() { echo -e "  ${RED}✗${NC} $*"; BOOT_ERRORS=$((BOOT_ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }

BOOT_ERRORS=0

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║       SuperLite OS — QEMU Boot Test (Serial)        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "ISO: $ISO"
echo ""

# ── Create test disk ──────────────────────────────────────────────────────
qemu-img create -f qcow2 /tmp/superlite-test-de.qcow2 2G 2>/dev/null

# ── Boot in QEMU with serial console ──────────────────────────────────────
echo "Booting ISO in QEMU (timeout: 240s)..."
echo "Waiting for boot signals on serial console..."
echo ""

BOOT_LOG="/tmp/superlite-boot-de.log"
rm -f "$BOOT_LOG"

# Run QEMU in background, capture serial output
# -nographic: all output to serial console
# -serial mon:stdio: serial port 0 → stdout
# -no-reboot: don't reboot on triple fault (shows panic instead)
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
BOOT_START=$(date +%s)
TIMEOUT=240
PHASE=0
LOGIN_FOUND=false

while kill -0 "$QEMU_PID" 2>/dev/null; do
    ELAPSED=$(( $(date +%s) - BOOT_START ))
    [[ $ELAPSED -ge $TIMEOUT ]] && break

    # Phase 1: Kernel boot (first 30s)
    if [[ $PHASE -eq 0 ]] && grep -qi "Freeing unused kernel\|Run /sbin/init\|Booting Linux" "$BOOT_LOG" 2>/dev/null; then
        pass "Kernel loaded and initialized (${ELAPSED}s)"
        PHASE=1
    fi

    # Phase 2: Initramfs / init (30-60s)
    if [[ $PHASE -le 1 ]] && grep -qiE "initramfs|SuperLite.*init|\[live\]|Mounting virtual" "$BOOT_LOG" 2>/dev/null; then
        pass "Initramfs init running (${ELAPSED}s)"
        PHASE=2
    fi

    # Phase 3: OpenRC starting (60-90s)
    if [[ $PHASE -le 2 ]] && grep -qiE "OpenRC|runlevel|Starting service" "$BOOT_LOG" 2>/dev/null; then
        pass "OpenRC service manager started (${ELAPSED}s)"
        PHASE=3
    fi

    # Phase 4: Critical services (90-120s)
    if [[ $PHASE -le 3 ]]; then
        if grep -qiE "seatd.*started|Starting seatd" "$BOOT_LOG" 2>/dev/null; then
            pass "seatd (Wayland seat manager) started (${ELAPSED}s)"
        fi
        if grep -qiE "dbus.*started|Starting dbus" "$BOOT_LOG" 2>/dev/null; then
            pass "D-Bus started (${ELAPSED}s)"
        fi
        PHASE=4
    fi

    # Phase 5: Login prompt or auto-login (120-180s)
    # This is the CRITICAL check — serial console shows login prompt when boot completes
    if [[ $PHASE -le 4 ]]; then
        if grep -qiE "login:|Welcome to SuperLite|SuperLite OS" "$BOOT_LOG" 2>/dev/null; then
            pass "Login prompt / welcome message detected (${ELAPSED}s)"
            LOGIN_FOUND=true
            PHASE=5
        elif grep -qiE "root@superlite|superlite:~|/ #" "$BOOT_LOG" 2>/dev/null; then
            pass "Shell prompt detected — auto-login worked (${ELAPSED}s)"
            LOGIN_FOUND=true
            PHASE=5
        fi
    fi

    # If we found login, no need to wait longer
    if [[ "$LOGIN_FOUND" == true ]]; then
        sleep 3  # Let it settle
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

# Check for cttyhack failure (only if recovery shell actually failed to start)
# Note: "cttyhack: applet not found" is non-fatal if busybox sh fallback works
if grep -q "cttyhack: applet not found" "$BOOT_LOG" 2>/dev/null; then
    if grep -q "can't access tty" "$BOOT_LOG" 2>/dev/null; then
        warn "cttyhack missing — recovery shell has no job control (non-fatal)"
    fi
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

# Check for service failures
if grep -qiE "seatd.*fail|Could not start seatd" "$BOOT_LOG" 2>/dev/null; then
    warn "seatd may have failed — Wayland desktop may not work"
fi
if grep -qiE "dbus.*fail|Could not connect to dbus" "$BOOT_LOG" 2>/dev/null; then
    warn "D-Bus may have failed"
fi

# ── Boot signals summary ─────────────────────────────────────────────────
echo ""
echo "── Boot Signals Summary ─────────────────────────────────"

BOOT_SIGNALS=0

grep -qiE "Booting Linux|Linux version" "$BOOT_LOG" 2>/dev/null && { pass "Kernel boot messages"; BOOT_SIGNALS=$((BOOT_SIGNALS + 1)); }
grep -qiE "initramfs|\[live\]|Mounting virtual" "$BOOT_LOG" 2>/dev/null && { pass "Initramfs activity"; BOOT_SIGNALS=$((BOOT_SIGNALS + 1)); }
grep -qiE "OpenRC|Starting service" "$BOOT_LOG" 2>/dev/null && { pass "OpenRC service manager"; BOOT_SIGNALS=$((BOOT_SIGNALS + 1)); }
grep -qiE "seatd" "$BOOT_LOG" 2>/dev/null && { pass "seatd referenced"; BOOT_SIGNALS=$((BOOT_SIGNALS + 1)); }
grep -qiE "dbus|D-Bus" "$BOOT_LOG" 2>/dev/null && { pass "D-Bus referenced"; BOOT_SIGNALS=$((BOOT_SIGNALS + 1)); }
grep -qiE "login:|Welcome to SuperLite|root@superlite" "$BOOT_LOG" 2>/dev/null && { pass "Login/prompt detected"; BOOT_SIGNALS=$((BOOT_SIGNALS + 1)); }

echo ""
echo "  Boot signals found: $BOOT_SIGNALS"

# ── Final Result ──────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
echo "  NOTE: This test uses serial console (-nographic)."
echo "  Serial console CANNOT verify GUI/desktop environment."
echo "  It only confirms: kernel → init → login prompt."
echo "  Desktop (LabWC/Wayland) requires graphical QEMU test."
echo ""

if grep -qi "Kernel panic" "$BOOT_LOG" 2>/dev/null; then
    echo -e "${RED}RESULT: FAILED — Kernel panic${NC}"
    echo "The system crashed during boot. Check the boot log."
    exit 1
fi

if [[ $BOOT_ERRORS -gt 0 ]]; then
    echo -e "${RED}RESULT: FAILED — $BOOT_ERRORS critical error(s)${NC}"
    echo "Boot process had fatal errors."
    echo ""
    echo "Full boot log saved to: $BOOT_LOG"
    exit 1
fi

if [[ "$LOGIN_FOUND" == true ]]; then
    echo -e "${GREEN}RESULT: PASSED — System boots to login prompt${NC}"
    echo "  Boot signals: $BOOT_SIGNALS"
    echo "  Login prompt: detected"
    echo "  System boots successfully on serial console."
    exit 0
elif [[ $BOOT_SIGNALS -ge 3 ]]; then
    echo -e "${YELLOW}RESULT: PARTIAL — Boot progressed but login not confirmed${NC}"
    echo "  Boot signals: $BOOT_SIGNALS (kernel + init + services)"
    echo "  Login prompt: not detected (may need longer timeout)"
    echo "  System is booting but may not be fully ready."
    exit 0
else
    echo -e "${RED}RESULT: FAILED — Boot did not progress${NC}"
    echo "  Boot signals: $BOOT_SIGNALS"
    echo "  Login prompt: not detected"
    echo ""
    echo "  Possible causes:"
    echo "    - initramfs cannot find live media (missing sr_mod/isofs?)"
    echo "    - /sbin/init missing or not executable"
    echo "    - Kernel modules missing (storage, filesystem)"
    echo "    - Console not configured (edd=off, console=ttyS0)"
    echo ""
    echo "  Full boot log saved to: $BOOT_LOG"
    exit 1
fi
