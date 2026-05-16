#!/bin/bash
# ============================================================================
# SuperLite OS — QEMU Simple Debug
# Run QEMU with serial console + monitor on stdio
# ============================================================================
# Usage:
#   ./run-qemu-simple.sh
#
# Keybindings (QEMU):
#   Ctrl+A then C   : Switch to QEMU monitor
#   Ctrl+A then X   : Kill QEMU
#   Ctrl+A then H   : Toggle serial console
#
# In QEMU Monitor:
#   sendkey alt-f1  : Switch to tty1
#   sendkey alt-f2  : Switch to tty2
#   sendkey alt-f3  : Switch to tty3
#   sendkey alt-f4  : Switch to tty4
#   sendkey alt-f5  : Switch to tty5
#   sendkey alt-f6  : Switch to tty6
#   info status     : VM status
#   screendump      : Save screenshot (pnm file)
#   quit            : Exit QEMU
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO=""
MEMORY="2G"

# Auto-detect ISO
ISO=$(find "$SCRIPT_DIR/output" -name "*.iso" -type f 2>/dev/null | head -1)
if [[ -z "$ISO" ]]; then
    ISO=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.iso" -type f 2>/dev/null | head -1)
fi

[[ -z "$ISO" ]] && { echo "ERROR: No ISO found. Build first with: ./build.sh --docker"; exit 1; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         SuperLite OS — QEMU Simple Debug                   ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ISO: $ISO"
echo "║  Memory: $MEMORY"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Keybindings:                                              ║"
echo "║    Ctrl+A then C : QEMU Monitor                            ║"
echo "║    Ctrl+A then X : Kill QEMU                               ║"
echo "║                                                            ║"
echo "║  In Monitor:                                               ║"
echo "║    sendkey alt-f1  → tty1                                  ║"
echo "║    sendkey alt-f2  → tty2                                  ║"
echo "║    sendkey alt-f3  → tty3                                  ║"
echo "║    sendkey alt-f4  → tty4                                  ║"
echo "║    sendkey alt-f5  → tty5                                  ║"
echo "║    sendkey alt-f6  → tty6                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

exec qemu-system-x86_64 \
    -m "$MEMORY" \
    -cdrom "$ISO" \
    -boot d \
    -no-reboot \
    -vga virtio \
    -nographic \
    -serial mon:stdio \
    -append "console=ttyS0,115200 console=tty0"
