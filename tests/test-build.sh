#!/bin/bash
# SuperLite OS — Build Test
set -euo pipefail

ISO=$(ls superlite-os-*.iso 2>/dev/null | head -1)
[[ -z "$ISO" ]] && { echo "FAIL: No ISO found"; exit 1; }

echo "Testing: $ISO"
ERRORS=0

# Check ISO exists and has size > 100MB
SIZE=$(stat -c%s "$ISO" 2>/dev/null || stat -f%z "$ISO")
if [[ "$SIZE" -lt 104857600 ]]; then
    echo "  ✗ ISO too small ($SIZE bytes)"
    ((ERRORS++))
else
    echo "  ✓ ISO size: $((SIZE/1048576)) MB"
fi

# Check ISO is valid
if file "$ISO" | grep -qi "ISO 9660"; then
    echo "  ✓ Valid ISO 9660"
else
    echo "  ✗ Not a valid ISO"
    ((ERRORS++))
fi

# ── Check for specific boot files ─────────────────────────────────────────────
# Use multiple methods to verify file presence in the ISO

check_iso_file() {
    local pattern="$1"
    local label="$2"

    # Method 1: xorriso find (most reliable)
    if command -v xorriso &>/dev/null; then
        if xorriso -indev "$ISO" -find / -maxdepth 4 2>/dev/null | grep -qiE "$pattern"; then
            echo "  ✓ $label"
            return 0
        fi
    fi

    # Method 2: isoinfo recursive-ish check
    if command -v isoinfo &>/dev/null; then
        # Try listing specific directories
        for dir in "/" "/boot" "/boot/syslinux" "/EFI" "/EFI/BOOT" "/live"; do
            if isoinfo -R -l -i "$ISO" -path-list "$dir" 2>/dev/null | grep -qiE "$pattern"; then
                echo "  ✓ $label"
                return 0
            fi
        done
        # Also try full listing
        if isoinfo -l -i "$ISO" 2>/dev/null | grep -qiE "$pattern"; then
            echo "  ✓ $label"
            return 0
        fi
    fi

    # Method 3: 7z (if available)
    if command -v 7z &>/dev/null; then
        if 7z l "$ISO" 2>/dev/null | grep -qiE "$pattern"; then
            echo "  ✓ $label"
            return 0
        fi
    fi

    # Method 4: bsdtar (if available)
    if command -v bsdtar &>/dev/null; then
        if bsdtar -tf "$ISO" 2>/dev/null | grep -qiE "$pattern"; then
            echo "  ✓ $label"
            return 0
        fi
    fi

    echo "  ⚠ $label not detected"
    return 1
}

check_iso_file "EFI|BOOTX64|efi\.img" "EFI boot"
check_iso_file "isolinux|syslinux|isolinux\.bin" "Legacy BIOS boot (syslinux)"
check_iso_file "rootfs\.squashfs|\.sfs" "Squashfs rootfs"

# Summary
echo ""
if [[ "$ERRORS" -gt 0 ]]; then
    echo "FAILED: $ERRORS error(s)"
    exit 1
else
    echo "All checks passed!"
fi
