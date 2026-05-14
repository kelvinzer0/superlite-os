#!/bin/sh
# ============================================================================
# SuperLite OS — Theme Installer
# Downloads WhiteSur-Light GTK theme from GitHub
# Called from setup-rootfs.sh inside chroot
# ============================================================================
set -e

echo "[themes] Installing WhiteSur-Light theme..."

mkdir -p /usr/share/themes

WHITESUR_URL="https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/heads/master.tar.gz"

if command -v wget >/dev/null 2>&1; then
    wget -q -O /tmp/whitesur.tar.gz "$WHITESUR_URL" 2>/dev/null || true
fi

if [ -f /tmp/whitesur.tar.gz ]; then
    tar xzf /tmp/whitesur.tar.gz -C /tmp/ 2>/dev/null || true
    WHITESUR_DIR=$(ls -d /tmp/WhiteSur-gtk-theme-* 2>/dev/null | head -1)
    if [ -n "$WHITESUR_DIR" ] && [ -d "$WHITESUR_DIR" ]; then
        mkdir -p /usr/share/themes/WhiteSur-Light
        cp -r "$WHITESUR_DIR"/src/main/gtk-3.0/WhiteSur-Light /usr/share/themes/ 2>/dev/null || true
        cp -r "$WHITESUR_DIR"/src/main/gtk-2.0/WhiteSur-Light /usr/share/themes/ 2>/dev/null || true
        echo "[themes] WhiteSur-Light installed"
    fi
    rm -rf /tmp/whitesur.tar.gz /tmp/WhiteSur-gtk-theme-* 2>/dev/null
else
    echo "[themes] WARNING: Could not download WhiteSur theme, falling back to Adwaita"
fi

echo "[themes] Done."
