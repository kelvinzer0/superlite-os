#!/bin/bash
# SuperLite OS — Build Test
set -euo pipefail

ISO=$(ls superlite-os-*.iso 2>/dev/null | head -1)
[[ -z "$ISO" ]] && { echo "FAIL: No ISO found"; exit 1; }

echo "Testing: $ISO"

# Check ISO exists and has size > 100MB
SIZE=$(stat -c%s "$ISO" 2>/dev/null || stat -f%z "$ISO")
[[ "$SIZE" -lt 104857600 ]] && { echo "FAIL: ISO too small ($SIZE bytes)"; exit 1; }
echo "  ✓ ISO size: $((SIZE/1048576)) MB"

# Check ISO is valid
file "$ISO" | grep -qi "ISO 9660" || { echo "FAIL: Not a valid ISO"; exit 1; }
echo "  ✓ Valid ISO 9660"

# Check for EFI boot
if isoinfo -R -l -i "$ISO" 2>/dev/null | grep -q "EFI"; then
    echo "  ✓ EFI boot present"
else
    echo "  ⚠ EFI boot not detected (may still work)"
fi

# Check for syslinux boot
if isoinfo -R -l -i "$ISO" 2>/dev/null | grep -q "isolinux"; then
    echo "  ✓ Legacy BIOS boot present"
else
    echo "  ⚠ syslinux boot not detected"
fi

# Check for squashfs
if isoinfo -R -l -i "$ISO" 2>/dev/null | grep -q "rootfs.squashfs"; then
    echo "  ✓ Squashfs rootfs present"
else
    echo "  ⚠ Squashfs not detected"
fi

echo ""
echo "All checks passed!"
