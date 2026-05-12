#!/bin/bash
# SuperLite OS — QEMU Boot Test
# Usage: ./test_boot.sh [arch] [mode]
#   mode: serial (headless), console (nographic), graphic

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")/base"
ARCH="${1:-x86_64}"
MODE="${2:-serial}"

echo "============================================"
echo "  SuperLite OS — QEMU Boot Test"
echo "  Arch: $ARCH"
echo "  Mode: $MODE"
echo "============================================"
echo ""

# Find kernel
KERNEL="$BASE_DIR/vmlinuz-$ARCH"
if [ ! -f "$KERNEL" ]; then
    # Try host kernel
    KERNEL="/boot/vmlinuz-$(uname -r)"
    if [ ! -f "$KERNEL" ]; then
        echo "Error: No kernel found"
        echo "Expected: $BASE_DIR/vmlinuz-$ARCH"
        exit 1
    fi
    echo "Using host kernel: $KERNEL"
fi

# Find initramfs
INITRD="$BASE_DIR/initramfs-${ARCH}.cpio.gz"
if [ ! -f "$INITRD" ]; then
    echo "Error: Initramfs not found: $INITRD"
    exit 1
fi

echo "Kernel:    $KERNEL ($(stat -c%s "$KERNEL" | awk '{printf "%.1fMB", $1/1048576}'))"
echo "Initramfs: $INITRD ($(stat -c%s "$INITRD" | awk '{printf "%.0fKB", $1/1024}'))"
echo ""

# Build QEMU command
case "$ARCH" in
    x86_64)
        QEMU="qemu-system-x86_64"
        MACHINE="q35"
        CPU="max"
        ;;
    i686)
        QEMU="qemu-system-i386"
        MACHINE="pc"
        CPU="max"
        ;;
    aarch64)
        QEMU="qemu-system-aarch64"
        MACHINE="virt"
        CPU="cortex-a72"
        ;;
    armv7)
        QEMU="qemu-system-arm"
        MACHINE="versatilepb"
        CPU="cortex-a9"
        ;;
    riscv64)
        QEMU="qemu-system-riscv64"
        MACHINE="virt"
        CPU="rv64"
        ;;
    *)
        echo "Unsupported arch: $ARCH"
        exit 1
        ;;
esac

# Common QEMU args
COMMON_ARGS=(
    -kernel "$KERNEL"
    -initrd "$INITRD"
    -m 256M
    -smp 2
    -no-reboot
    -append "console=ttyS0,115200n8 earlyprintk=serial oops=panic panic=1"
)

# Network (user mode)
NET_ARGS=(
    -netdev user,id=net0
    -device virtio-net-pci,netdev=net0
)

# Mode-specific args
case "$MODE" in
    serial)
        # Headless, serial output to terminal
        MODE_ARGS=(
            -nographic
            -serial mon:stdio
        )
        echo "Starting QEMU (serial mode, Ctrl+A X to quit)..."
        echo "============================================"
        echo ""
        exec "$QEMU" \
            -M "$MACHINE" \
            -cpu "$CPU" \
            "${COMMON_ARGS[@]}" \
            "${NET_ARGS[@]}" \
            "${MODE_ARGS[@]}"
        ;;
    console)
        # Graphic with serial console
        echo "Starting QEMU (graphic mode)..."
        exec "$QEMU" \
            -M "$MACHINE" \
            -cpu "$CPU" \
            "${COMMON_ARGS[@]}" \
            "${NET_ARGS[@]}" \
            -serial stdio
        ;;
    graphic)
        # Full graphic
        echo "Starting QEMU (full graphic mode)..."
        exec "$QEMU" \
            -M "$MACHINE" \
            -cpu "$CPU" \
            "${COMMON_ARGS[@]}" \
            "${NET_ARGS[@]}" \
            -display gtk
        ;;
    test)
        # Non-interactive test: boot and check for panic
        echo "Running boot test (10s timeout)..."
        timeout 10 "$QEMU" \
            -M "$MACHINE" \
            -cpu "$CPU" \
            "${COMMON_ARGS[@]}" \
            -nographic \
            -serial mon:stdio \
            -no-shutdown \
            2>&1 | tee /tmp/qemu-test.log
        
        EXIT_CODE=$?
        echo ""
        echo "============================================"
        if [ $EXIT_CODE -eq 124 ]; then
            echo "✓ Boot test PASSED (ran for 10s without panic)"
        elif grep -q "Kernel panic" /tmp/qemu-test.log; then
            echo "✗ Boot test FAILED (kernel panic detected)"
            grep -A5 "Kernel panic" /tmp/qemu-test.log
        else
            echo "? Boot test finished (exit code: $EXIT_CODE)"
        fi
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Use: serial, console, graphic, test"
        exit 1
        ;;
esac
