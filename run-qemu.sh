#!/bin/bash
# ============================================================================
# SuperLite OS — QEMU Runner
# Run the ISO in a virtual machine for testing.
# ============================================================================
# Usage:
#   ./run-qemu.sh                        # Run with defaults
#   ./run-qemu.sh --iso path/to/file.iso # Custom ISO
#   ./run-qemu.sh --memory 2G            # More RAM
#   ./run-qemu.sh --gui                  # GUI mode (no -nographic)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO=""
MEMORY="1G"
GUI=false
KVM=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)      ISO="$2"; shift 2 ;;
        --memory)   MEMORY="$2"; shift 2 ;;
        --gui)      GUI=true; shift ;;
        --no-kvm)   KVM=false; shift ;;
        -h|--help)
            echo "Usage: $0 [--iso PATH] [--memory SIZE] [--gui] [--no-kvm]"
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

echo "SuperLite OS — QEMU Runner"
echo "  ISO:      $ISO"
echo "  Memory:   $MEMORY"
echo "  Mode:     $([ "$GUI" = true ] && echo "GUI" || echo "Serial console")"
echo "  KVM:      $([ "$KVM" = true ] && echo "yes" || echo "no")"
echo ""

QEMU_ARGS=(
    -m "$MEMORY"
    -cdrom "$ISO"
    -boot d
    -no-reboot
)

# KVM acceleration (Linux only)
if [[ "$KVM" == true ]] && [[ -e /dev/kvm ]]; then
    QEMU_ARGS+=(-enable-kvm -cpu host)
else
    QEMU_ARGS+=(-cpu qemu64)
fi

if [[ "$GUI" == true ]]; then
    QEMU_ARGS+=(-vga virtio)
else
    QEMU_ARGS+=(-nographic -serial mon:stdio)
fi

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
