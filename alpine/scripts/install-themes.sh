#!/bin/sh
# ============================================================================
# SuperLite OS — Theme Installer
# Builds and installs WhiteSur-Light GTK theme
# Called from setup-rootfs.sh inside chroot
# ============================================================================
set -e

echo "[themes] Installing WhiteSur-Light theme..."

mkdir -p /usr/share/themes

# Check if sassc is available (needed to build GTK theme)
if ! command -v sassc >/dev/null 2>&1; then
    echo "[themes] sassc not found, installing..."
    apk add sassc 2>/dev/null || true
fi

# Download WhiteSur theme source
WHITESUR_URL="https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/heads/master.tar.gz"

if command -v wget >/dev/null 2>&1; then
    wget -q -O /tmp/whitesur.tar.gz "$WHITESUR_URL" 2>/dev/null || true
fi

if [ ! -f /tmp/whitesur.tar.gz ]; then
    echo "[themes] WARNING: Could not download WhiteSur theme, falling back to Adwaita"
    exit 0
fi

tar xzf /tmp/whitesur.tar.gz -C /tmp/ 2>/dev/null || true
WHITESUR_DIR=$(ls -d /tmp/WhiteSur-gtk-theme-* 2>/dev/null | head -1)

if [ -z "$WHITESUR_DIR" ] || [ ! -d "$WHITESUR_DIR" ]; then
    echo "[themes] WARNING: Could not extract WhiteSur theme"
    rm -f /tmp/whitesur.tar.gz
    exit 0
fi

# Install only Light variant to save space
cd "$WHITESUR_DIR"
if [ -f "./install.sh" ]; then
    chmod +x ./install.sh
    # -c standard = default color scheme
    # -o normal = normal opacity
    # --dest /usr/share/themes = install location
    # Only install Light variant (no dark)
    ./install.sh -c standard -o normal --dest /usr/share/themes 2>&1 | tail -5 || {
        echo "[themes] WARNING: WhiteSur install.sh failed, trying manual copy..."
        # Fallback: try to find pre-built theme files
        if [ -d "src/WhiteSur-Light" ]; then
            cp -r src/WhiteSur-Light /usr/share/themes/ 2>/dev/null || true
        fi
    }
    echo "[themes] WhiteSur-Light installed"
else
    echo "[themes] WARNING: install.sh not found"
fi

cd /
rm -rf /tmp/whitesur.tar.gz "$WHITESUR_DIR" 2>/dev/null

# Refresh icon cache
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

echo "[themes] Done."
