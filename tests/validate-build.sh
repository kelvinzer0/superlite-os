#!/bin/bash
# ============================================================================
# SuperLite OS — Build Validation (Yocto)
# Validates Yocto build output without QEMU
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${TOP_DIR}/build"
MACHINE="superlite-x86_64"
IMG_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/${MACHINE}"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo -e "  \033[0;32m✓\033[0m $*"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  \033[0;31m✗\033[0m $*"; }

echo ""
echo "═══════════════════════════════════════════════"
echo "SuperLite OS — Build Validation"
echo "═══════════════════════════════════════════════"
echo ""

# ── Layer structure ─────────────────────────────────────────────────────────
echo "Layer Structure:"
LAYER="${TOP_DIR}/meta-superlite"
[ -f "${LAYER}/conf/layer.conf" ] && pass "layer.conf exists" || fail "layer.conf missing"
[ -f "${LAYER}/conf/machine/superlite-x86_64.conf" ] && pass "Machine config exists" || fail "Machine config missing"
[ -f "${LAYER}/conf/distro/superlite.conf" ] && pass "Distro config exists" || fail "Distro config missing"
[ -f "${LAYER}/recipes-core/images/superlite-os-image.bb" ] && pass "Image recipe exists" || fail "Image recipe missing"

echo ""
echo "Package Groups:"
for pkg in base desktop network apps; do
    [ -f "${LAYER}/recipes-core/packagegroups/packagegroup-superlite-${pkg}.bb" ] && \
        pass "packagegroup-superlite-${pkg}" || fail "packagegroup-superlite-${pkg} missing"
done

echo ""
echo "Custom Recipes:"
for recipe in labwc waybar foot tofi; do
    [ -f "${LAYER}/recipes-graphics/${recipe}/${recipe}.bb" ] && \
        pass "${recipe} recipe" || fail "${recipe} recipe missing"
done
for recipe in superlite-live superlite-dotfiles superlite-hooks superlite-themes; do
    [ -f "${LAYER}/recipes-apps/${recipe}/${recipe}.bb" ] && \
        pass "${recipe} recipe" || fail "${recipe} recipe missing"
done

echo ""
echo "Kernel:"
[ -f "${LAYER}/recipes-kernel/linux-superlite/linux-superlite.bb" ] && pass "Kernel recipe" || fail "Kernel recipe missing"
[ -f "${LAYER}/recipes-kernel/linux-superlite/linux-superlite/superlite.cfg" ] && pass "Base kernel config" || fail "Base kernel config missing"
[ -f "${LAYER}/recipes-kernel/linux-superlite/linux-superlite/gpu.cfg" ] && pass "GPU kernel config" || fail "GPU kernel config missing"
[ -f "${LAYER}/recipes-kernel/linux-superlite/linux-superlite/wifi.cfg" ] && pass "WiFi kernel config" || fail "WiFi kernel config missing"
[ -f "${LAYER}/recipes-kernel/linux-superlite/linux-superlite/live-boot.cfg" ] && pass "Live-boot kernel config" || fail "Live-boot kernel config missing"

echo ""
echo "WIC:"
[ -f "${LAYER}/wic/superlite-live.wks" ] && pass "WKS file" || fail "WKS file missing"

# ── Build artifacts (if build exists) ──────────────────────────────────────
if [ -d "$IMG_DIR" ]; then
    echo ""
    echo "Build Artifacts:"
    ls "${IMG_DIR}/superlite-os-image-"*.squashfs-xz &>/dev/null && \
        pass "Squashfs image found" || fail "No squashfs image"
    ls "${IMG_DIR}/bzImage"* &>/dev/null && \
        pass "Kernel image found" || fail "No kernel image"
else
    echo ""
    echo "Build Artifacts: (no build found — run 'make build' first)"
fi

# ── Legacy files (backward compat) ────────────────────────────────────────
echo ""
echo "Legacy Scripts (backward compatibility):"
[ -f "${TOP_DIR}/build.sh" ] && pass "build.sh" || fail "build.sh missing"
[ -f "${TOP_DIR}/Makefile" ] && pass "Makefile" || fail "Makefile missing"
[ -d "${TOP_DIR}/alpine" ] && pass "alpine/ directory (legacy)" || fail "alpine/ directory missing"
[ -d "${TOP_DIR}/dotfiles" ] && pass "dotfiles/ directory" || fail "dotfiles/ directory missing"

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
if [ "$FAIL" -eq 0 ]; then
    echo -e "\033[0;32mAll checks passed!\033[0m"
else
    echo -e "\033[0;31mSome checks failed.\033[0m"
fi
echo "═══════════════════════════════════════════════"

exit $FAIL
