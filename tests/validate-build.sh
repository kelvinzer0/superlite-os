#!/bin/bash
# ============================================================================
# SuperLite OS — Build Validation
# Validates Alpine-native project structure
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo -e "  \033[0;32m✓\033[0m $*"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  \033[0;31m✗\033[0m $*"; }

echo ""
echo "═══════════════════════════════════════════════"
echo "SuperLite OS — Build Validation (Alpine Native)"
echo "═══════════════════════════════════════════════"
echo ""

# ── Core build files ───────────────────────────────────────────────────────
echo "Core Build Files:"
[ -f "${TOP_DIR}/build.sh" ] && pass "build.sh" || fail "build.sh missing"
[ -x "${TOP_DIR}/build.sh" ] && pass "build.sh is executable" || fail "build.sh not executable"
[ -f "${TOP_DIR}/aports/scripts/mkimg.superlite.sh" ] && pass "mkimg.superlite.sh (profile)" || fail "mkimg.superlite.sh missing"
[ -f "${TOP_DIR}/aports/scripts/genapkovl-superlite.sh" ] && pass "genapkovl-superlite.sh (overlay)" || fail "genapkovl-superlite.sh missing"

echo ""
echo "Package References:"
[ -f "${TOP_DIR}/alpine/configs/packages.list" ] && pass "packages.list" || fail "packages.list missing"
[ -f "${TOP_DIR}/alpine/configs/repositories" ] && pass "repositories" || fail "repositories missing"

echo ""
echo "Dotfiles:"
[ -d "${TOP_DIR}/dotfiles/.config/labwc" ] && pass "LabWC config" || fail "LabWC config missing"
[ -d "${TOP_DIR}/dotfiles/.config/waybar" ] && pass "Waybar config" || fail "Waybar config missing"
[ -d "${TOP_DIR}/dotfiles/.config/foot" ] && pass "Foot config" || fail "Foot config missing"
[ -d "${TOP_DIR}/dotfiles/.config/mako" ] && pass "Mako config" || fail "Mako config missing"
[ -d "${TOP_DIR}/dotfiles/.config/tofi" ] && pass "Tofi config" || fail "Tofi config missing"

echo ""
echo "Themes:"
[ -f "${TOP_DIR}/alpine/packages/themes/WhiteSur-Light.tar.xz" ] && pass "WhiteSur-Light theme" || fail "WhiteSur-Light missing"
[ -f "${TOP_DIR}/alpine/packages/themes/Haiku.gz" ] && pass "Haiku icons" || fail "Haiku icons missing"
[ -f "${TOP_DIR}/alpine/packages/themes/ohsnap.zip" ] && pass "OhSnap font" || fail "OhSnap font missing"

echo ""
echo "CI/CD:"
[ -f "${TOP_DIR}/.github/workflows/build.yml" ] && pass "GitHub Actions workflow" || fail "build.yml missing"

echo ""
echo "NOT Yocto (verify clean removal):"
[ ! -d "${TOP_DIR}/meta-superlite" ] && pass "meta-superlite removed" || fail "meta-superlite still exists!"

# ── Build artifacts ────────────────────────────────────────────────────────
echo ""
ISO_COUNT=$(find "${TOP_DIR}/output" -name "*.iso" 2>/dev/null | wc -l)
if [ "$ISO_COUNT" -gt 0 ]; then
    echo "Build Artifacts:"
    find "${TOP_DIR}/output" -name "*.iso" -exec ls -lh {} \; | while read line; do
        pass "$line"
    done
else
    echo "Build Artifacts: (none — run 'make docker' to build)"
fi

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
