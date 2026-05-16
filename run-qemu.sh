#!/bin/bash
# ============================================================================
# SuperLite OS — QEMU Runner
# Run the ISO in a virtual machine for testing.
# ============================================================================
# Usage:
#   ./run-qemu.sh                        # Run with defaults (serial console)
#   ./run-qemu.sh --iso path/to/file.iso # Custom ISO
#   ./run-qemu.sh --memory 2G            # More RAM
#   ./run-qemu.sh --gui                  # GUI mode (VGA output)
#   ./run-qemu.sh --debug                # Debug mode (serial + monitor)
# ============================================================================
# Keybindings (in -nographic mode):
#   Ctrl+A then C   : Switch to QEMU monitor
#   Ctrl+A then X   : Kill QEMU
#   Ctrl+A then H   : Toggle serial console
#
# In QEMU Monitor:
#   sendkey alt-f1  : Switch to tty1
#   sendkey alt-f2  : Switch to tty2
#   ...
#   sendkey alt-f6  : Switch to tty6
#   info status     : VM status
#   screendump      : Save screenshot
#   quit            : Exit QEMU
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO=""
MEMORY="1G"
GUI=false
DEBUG=false
KVM=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)      ISO="$2"; shift 2 ;;
        --memory)   MEMORY="$2"; shift 2 ;;
        --gui)      GUI=true; shift ;;
        --debug)    DEBUG=true; shift ;;
        --no-kvm)   KVM=false; shift ;;
        -h|--help)
            echo "Usage: $0 [--iso PATH] [--memory SIZE] [--gui] [--debug] [--no-kvm]"
            echo ""
            echo "Modes:"
            echo "  (default)    Serial console on stdio + QEMU monitor"
            echo "  --gui        VGA output (separate window)"
            echo "  --debug      Serial + monitor + boot log"
            echo ""
            echo "Keybindings (serial mode):"
            echo "  Ctrl+A then C  : QEMU monitor"
            echo "  Ctrl+A then X  : Kill QEMU"
            echo ""
            echo "QEMU Monitor commands:"
            echo "  sendkey alt-f1 : Switch to tty1"
            echo "  sendkey alt-f2 : Switch to tty2"
            echo "  sendkey alt-f3 : Switch to tty3"
            echo "  sendkey alt-f4 : Switch to tty4"
            echo "  sendkey alt-f5 : Switch to tty5"
            echo "  sendkey alt-f6 : Switch to tty6"
            echo "  info status    : VM status"
            echo "  screendump     : Save screenshot"
            echo "  quit           : Exit QEMU"
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

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         SuperLite OS — QEMU Runner                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ISO:       $ISO"
echo "║  Memory:    $MEMORY"
echo "║  Mode:      $([ "$GUI" = true ] && echo "GUI (VGA)" || echo "Serial console")"
echo "║  Debug:     $([ "$DEBUG" = true ] && echo "yes" || echo "no")"
echo "║  KVM:       $([ "$KVM" = true ] && echo "yes" || echo "no")"
echo "╠══════════════════════════════════════════════════════════════╣"
if [[ "$GUI" == false ]]; then
echo "║  Keybindings:                                              ║"
echo "║    Ctrl+A then C : QEMU Monitor                            ║"
echo "║    Ctrl+A then X : Kill QEMU                               ║"
echo "║                                                            ║"
echo "║  Monitor commands:                                         ║"
echo "║    sendkey alt-f1  → tty1                                  ║"
echo "║    sendkey alt-f2  → tty2                                  ║"
echo "║    sendkey alt-f3  → tty3                                  ║"
echo "║    sendkey alt-f4  → tty4                                  ║"
echo "║    sendkey alt-f5  → tty5                                  ║"
echo "║    sendkey alt-f6  → tty6                                  ║"
echo "║    info status     → VM status                             ║"
echo "║    screendump      → Screenshot                            ║"
echo "║    quit            → Exit                                  ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

QEMU_ARGS=(
    -m "$MEMORY"
    -cdrom "$ISO"
    -boot d
    -no-reboot
)

# KVM acceleration
if [[ "$KVM" == true ]] && [[ -e /dev/kvm ]]; then
    QEMU_ARGS+=(-enable-kvm -cpu host)
else
    QEMU_ARGS+=(-cpu qemu64)
fi

if [[ "$GUI" == true ]]; then
    # GUI mode - VGA output in window
    QEMU_ARGS+=(-vga virtio)
    if [[ "$DEBUG" == true ]]; then
        # Also add serial console to file
        QEMU_ARGS+=(-serial file:/tmp/superlite-serial.log)
        echo "[*] Serial output will be logged to: /tmp/superlite-serial.log"
        echo "[*] Monitor with: tail -f /tmp/superlite-serial.log"
    fi
else
    # Serial console mode
    QEMU_ARGS+=(
        -nographic
        -vga virtio
        -serial mon:stdio
    )
fi

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
