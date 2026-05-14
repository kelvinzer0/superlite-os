#!/bin/sh
# ============================================================================
# SuperLite OS — Theme Installer
# Installs pre-built themes from RiccardoPP's LabWC-Alpine-Netbook dotfiles:
#   - WhiteSur-Light GTK theme
#   - Haiku icon theme
#   - Misc OhSnap bitmap font
#
# Called from setup-rootfs.sh inside chroot
# Files expected at /tmp/themes/
# ============================================================================
set -e

echo "[themes] Installing themes from RiccardoPP's dotfiles..."

THEMES_DIR="/tmp/themes"

if [ ! -d "$THEMES_DIR" ]; then
    echo "[themes] WARNING: /tmp/themes not found, skipping"
    exit 0
fi

# ── 1. WhiteSur-Light GTK theme ─────────────────────────────────────────────
echo "[themes] Installing WhiteSur-Light..."
mkdir -p /usr/share/themes
if [ -f "$THEMES_DIR/WhiteSur-Light.tar.xz" ]; then
    tar xf "$THEMES_DIR/WhiteSur-Light.tar.xz" -C /usr/share/themes/ 2>/dev/null
    echo "[themes] WhiteSur-Light installed"
else
    echo "[themes] WARNING: WhiteSur-Light.tar.xz not found"
fi

# ── 2. Haiku icon theme ─────────────────────────────────────────────────────
echo "[themes] Installing Haiku icons..."
mkdir -p /usr/share/icons
if [ -f "$THEMES_DIR/Haiku.gz" ]; then
    tar xzf "$THEMES_DIR/Haiku.gz" -C /usr/share/icons/ 2>/dev/null
    echo "[themes] Haiku icons installed"
else
    echo "[themes] WARNING: Haiku.gz not found"
fi

# ── 3. Misc OhSnap font ─────────────────────────────────────────────────────
echo "[themes] Installing OhSnap font..."
mkdir -p /usr/share/fonts/misc
if [ -f "$THEMES_DIR/ohsnap.zip" ]; then
    cd /tmp
    unzip -o "$THEMES_DIR/ohsnap.zip" -d /tmp/ohsnap-extract 2>/dev/null || true
    # Find .pcf or .bdf font files and install
    find /tmp/ohsnap-extract -type f \( -name "*.pcf" -o -name "*.pcf.gz" -o -name "*.bdf" \) -exec cp {} /usr/share/fonts/misc/ \; 2>/dev/null || true
    rm -rf /tmp/ohsnap-extract
    echo "[themes] OhSnap font installed"
else
    echo "[themes] WARNING: ohsnap.zip not found"
fi

# ── 4. Refresh caches ───────────────────────────────────────────────────────
echo "[themes] Refreshing caches..."
fc-cache -f 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/Haiku 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
gtk-update-icon-cache /usr/share/themes/WhiteSur-Light 2>/dev/null || true

echo "[themes] All themes installed."
