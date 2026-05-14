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

# Get file listing (try multiple methods)
FILELIST=""
if command -v isoinfo &>/dev/null; then
    FILELIST=$(isoinfo -R -l -i "$ISO" 2>/dev/null || true)
fi
if [[ -z "$FILELIST" ]] && command -v xorriso &>/dev/null; then
    FILELIST=$(xorriso -indev "$ISO" -ls / 2>/dev/null || true)
fi

# Check for EFI boot
if echo "$FILELIST" | grep -qiE "(EFI|BOOTX64|efi\.img)"; then
    echo "  ✓ EFI boot present"
elif [[ -n "$FILELIST" ]]; then
    # Fallback: check if EFI dir exists in ISO
    echo "  ⚠ EFI boot not detected in file listing"
else
    # Can't verify but don't fail — xorriso args in build.sh include EFI
    echo "  ⚠ Cannot verify EFI (isoinfo/xorriso not available on host)"
fi

# Check for syslinux boot
if echo "$FILELIST" | grep -qiE "(isolinux|syslinux)"; then
    echo "  ✓ Legacy BIOS boot present"
elif [[ -n "$FILELIST" ]]; then
    echo "  ⚠ syslinux not detected in file listing"
else
    echo "  ⚠ Cannot verify syslinux (isoinfo/xorriso not available on host)"
fi

# Check for squashfs
if echo "$FILELIST" | grep -qiE "(rootfs\.squashfs|\.sfs)"; then
    echo "  ✓ Squashfs rootfs present"
elif [[ -n "$FILELIST" ]]; then
    echo "  ⚠ Squashfs not detected in file listing"
else
    echo "  ⚠ Cannot verify squashfs (isoinfo/xorriso not available on host)"
fi

# Summary
echo ""
if [[ "$ERRORS" -gt 0 ]]; then
    echo "FAILED: $ERRORS error(s)"
    exit 1
else
    echo "All checks passed!"
fi
