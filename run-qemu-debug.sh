#!/bin/bash
# ============================================================================
# SuperLite OS — QEMU Debug Monitor
# Monitor all TTYs and serial console simultaneously via tmux
# ============================================================================
# Usage:
#   ./run-qemu-debug.sh                        # Run with defaults
#   ./run-qemu-debug.sh --iso path/to/file.iso # Custom ISO
#   ./run-qemu-debug.sh --memory 2G            # More RAM
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO=""
MEMORY="2G"
KVM=true
SESSION="superlite-debug"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)      ISO="$2"; shift 2 ;;
        --memory)   MEMORY="$2"; shift 2 ;;
        --no-kvm)   KVM=false; shift ;;
        -h|--help)
            echo "Usage: $0 [--iso PATH] [--memory SIZE] [--no-kvm]"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# Auto-detect ISO
if [[ -z "$ISO" ]]; then
    ISO=$(find "$SCRIPT_DIR/output" -name "*.iso" -type f 2>/dev/null | head -1)
    if [[ -z "$ISO" ]]; then
        ISO=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.iso" -type f 2>/dev/null | head -1)
    fi
fi

[[ -z "$ISO" ]] && { echo "ERROR: No ISO found. Build first with: ./build.sh --docker"; exit 1; }
[[ -f "$ISO" ]] || { echo "ERROR: ISO not found: $ISO"; exit 1; }

# Kill existing session if any
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         SuperLite OS — QEMU Debug Monitor                  ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ISO:       $ISO"
echo "║  Memory:    $MEMORY"
echo "║  Session:   $SESSION"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Layout:                                                   ║"
echo "║  ┌─────────────────┬─────────────────┐                     ║"
echo "║  │   QEMU VGA      │   Serial (S0)   │                     ║"
echo "║  │   (tty1-tty6)   │   (ttyS0)       │                     ║"
echo "║  ├─────────────────┴─────────────────┤                     ║"
echo "║  │        QEMU Monitor               │                     ║"
echo "║  └───────────────────────────────────┘                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Keybindings (in tmux):                                    ║"
echo "║    Ctrl+B then 1-6 : Switch TTY (Alt+F1-F6 equivalent)    ║"
echo "║    Ctrl+B then M   : QEMU Monitor                          ║"
echo "║    Ctrl+B then S   : Serial Console                        ║"
echo "║    Ctrl+B then V   : VGA Window                            ║"
echo "║    Ctrl+A then C   : QEMU monitor (in serial window)       ║"
echo "║    Ctrl+A then X   : Kill QEMU                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Build QEMU args
QEMU_ARGS=(
    -m "$MEMORY"
    -cdrom "$ISO"
    -boot d
    -no-reboot
    -vga virtio
    -display none
    -serial unix:/tmp/qemu-serial.sock,server,nowait
    -monitor unix:/tmp/qemu-monitor.sock,server,nowait
    -chardev socket,id=serial1,path=/tmp/qemu-serial1.sock,server,nowait
    -serial chardev:serial1
)

# KVM
if [[ "$KVM" == true ]] && [[ -e /dev/kvm ]]; then
    QEMU_ARGS+=(-enable-kvm -cpu host)
else
    QEMU_ARGS+=(-cpu qemu64)
fi

# Cleanup old sockets
rm -f /tmp/qemu-serial.sock /tmp/qemu-monitor.sock /tmp/qemu-serial1.sock

# Start QEMU in background
echo "[*] Starting QEMU..."
qemu-system-x86_64 "${QEMU_ARGS[@]}" &
QEMU_PID=$!
sleep 2

# Check if QEMU is running
if ! kill -0 $QEMU_PID 2>/dev/null; then
    echo "ERROR: QEMU failed to start"
    exit 1
fi

echo "[*] QEMU started (PID: $QEMU_PID)"
echo "[*] Setting up tmux session..."

# Create tmux session with multiple panes
# Main VGA pane (we'll use socat to connect to serial sockets)

# Window 0: Serial Console (ttyS0)
tmux new-session -d -s "$SESSION" -n "serial-ttyS0" \
    "echo '=== Serial Console (ttyS0) ===' && socat - UNIX-CONNECT:/tmp/qemu-serial.sock"

# Window 1: Serial Console 2 (ttyS1)
tmux new-window -t "$SESSION" -n "serial-ttyS1" \
    "echo '=== Serial Console (ttyS1) ===' && socat - UNIX-CONNECT:/tmp/qemu-serial1.sock"

# Window 2: QEMU Monitor
tmux new-window -t "$SESSION" -n "qemu-monitor" \
    "echo '=== QEMU Monitor ===' && socat - UNIX-CONNECT:/tmp/qemu-monitor.sock"

# Window 3: Boot Log (capture serial output to file)
tmux new-window -t "$SESSION" -n "boot-log" \
    "echo '=== Boot Log (live) ===' && touch /tmp/superlite-boot.log && tail -f /tmp/superlite-boot.log"

# Window 4: VGA via VNC (optional - connect with vncviewer)
tmux new-window -t "$SESSION" -n "vga-info" \
    "echo '=== VGA Output ===' && echo '' && echo 'VGA is available via VNC on localhost:5900' && echo 'Connect with: vncviewer localhost:5900' && echo '' && echo 'Or use QEMU monitor to send keystrokes:' && echo '  sendkey alt-f1  (switch to tty1)' && echo '  sendkey alt-f2  (switch to tty2)' && echo '  sendkey alt-f3  (switch to tty3)' && echo '  sendkey alt-f4  (switch to tty4)' && echo '  sendkey alt-f5  (switch to tty5)' && echo '  sendkey alt-f6  (switch to tty6)' && echo '' && echo 'QEMU PID: $QEMU_PID' && echo '' && echo 'Press Ctrl+C to exit' && cat"

# Window 5: TTY Switcher
tmux new-window -t "$SESSION" -n "tty-switcher" \
    "echo '=== TTY Switcher ===' && echo '' && echo 'Quick commands (type in QEMU monitor window):' && echo '  sendkey alt-f1  → tty1 (VGA console)' && echo '  sendkey alt-f2  → tty2' && echo '  sendkey alt-f3  → tty3' && echo '  sendkey alt-f4  → tty4' && echo '  sendkey alt-f5  → tty5' && echo '  sendkey alt-f6  → tty6' && echo '' && echo 'Other useful commands:' && echo '  info status    → VM status' && echo '  info network   → Network info' && echo '  screendump     → Save screenshot' && echo '  quit           → Exit QEMU' && echo '' && echo 'Press Ctrl+C to exit' && cat"

# Start logging serial output to file
socat UNIX-CONNECT:/tmp/qemu-serial.sock STDOUT >> /tmp/superlite-boot.log 2>&1 &
LOG_PID=$!

# Select first window
tmux select-window -t "$SESSION:serial-ttyS0"

echo ""
echo "[*] tmux session '$SESSION' created"
echo "[*] Attaching to tmux session..."
echo ""
echo "TIPS:"
echo "  - Switch windows: Ctrl+B then 0-5"
echo "  - Switch panes:   Ctrl+B then arrow keys"
echo "  - Detach:         Ctrl+B then D"
echo "  - Kill QEMU:      Type 'quit' in QEMU Monitor window"
echo ""

# Attach to tmux
tmux attach -t "$SESSION"

# Cleanup when tmux exits
echo ""
echo "[*] Cleaning up..."
kill $QEMU_PID 2>/dev/null || true
kill $LOG_PID 2>/dev/null || true
rm -f /tmp/qemu-serial.sock /tmp/qemu-monitor.sock /tmp/qemu-serial1.sock /tmp/superlite-boot.log
echo "[*] Done"
