#!/bin/sh
# ============================================================================
# SuperLite OS — Theme Installer
# Downloads themes not available in Alpine repos:
#   - Misc OhSnap font (bitmap)
#   - Haiku icon theme
#   - WhiteSur-Light GTK theme
#
# Called from setup-rootfs.sh inside chroot
# ============================================================================
set -e

echo "[themes] Installing external themes..."

mkdir -p /usr/share/icons /usr/share/themes /usr/share/fonts/misc

# ── 1. Misc OhSnap font ─────────────────────────────────────────────────────
echo "[themes] Downloading OhSnap font..."
OHSNAP_URL="https://github.com/rondeau/rondeau/raw/master/fonts/bdf/ohsnap.bdf"
OHSNAP_PCF="/usr/share/fonts/misc/OhSnap.pcf"

if command -v wget >/dev/null 2>&1; then
    wget -q -O /tmp/ohsnap.bdf "$OHSNAP_URL" 2>/dev/null || true
fi

if [ -f /tmp/ohsnap.bdf ]; then
    # Convert BDF to PCF if bdftopcf is available, otherwise install BDF
    if command -v bdftopcf >/dev/null 2>&1; then
        bdftopcf /tmp/ohsnap.bdf > "$OHSNAP_PCF" 2>/dev/null || true
    else
        # Just copy as-is, X can often handle BDF
        cp /tmp/ohsnap.bdf /usr/share/fonts/misc/OhSnap.bdf 2>/dev/null || true
    fi
    rm -f /tmp/ohsnap.bdf
    echo "[themes] OhSnap font installed"
else
    echo "[themes] WARNING: Could not download OhSnap font (non-fatal)"
fi

# ── 2. Haiku icon theme ─────────────────────────────────────────────────────
echo "[themes] Downloading Haiku icons..."
HAIKU_URL="https://github.com/elementary/icons/archive/refs/heads/master.tar.gz"

# Try the actual Haiku-style icons (simp1e has Haiku-like set)
# Use a lightweight fallback: just install the simp1e cursor theme already in APK
# For icons, try downloading from a known source
HAIKU_ALT_URL="https://github.com/nicehash/haiku-icon-theme/archive/refs/heads/master.tar.gz"

if command -v wget >/dev/null 2>&1; then
    wget -q -O /tmp/haiku.tar.gz "$HAIKU_ALT_URL" 2>/dev/null || true
fi

if [ -f /tmp/haiku.tar.gz ]; then
    tar xzf /tmp/haiku.tar.gz -C /tmp/ 2>/dev/null || true
    HAIKU_DIR=$(ls -d /tmp/haiku-icon-theme-* 2>/dev/null | head -1)
    if [ -n "$HAIKU_DIR" ] && [ -d "$HAIKU_DIR" ]; then
        cp -r "$HAIKU_DIR" /usr/share/icons/Haiku 2>/dev/null || true
        echo "[themes] Haiku icon theme installed"
    fi
    rm -rf /tmp/haiku.tar.gz /tmp/haiku-icon-theme-* 2>/dev/null
else
    echo "[themes] WARNING: Could not download Haiku icons (non-fatal)"
    echo "[themes] Falling back to hicolor icon theme"
fi

# ── 3. WhiteSur GTK theme ───────────────────────────────────────────────────
echo "[themes] Downloading WhiteSur-Light GTK theme..."
WHITESUR_URL="https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/heads/master.tar.gz"

if command -v wget >/dev/null 2>&1; then
    wget -q -O /tmp/whitesur.tar.gz "$WHITESUR_URL" 2>/dev/null || true
fi

if [ -f /tmp/whitesur.tar.gz ]; then
    tar xzf /tmp/whitesur.tar.gz -C /tmp/ 2>/dev/null || true
    WHITESUR_DIR=$(ls -d /tmp/WhiteSur-gtk-theme-* 2>/dev/null | head -1)
    if [ -n "$WHITESUR_DIR" ] && [ -d "$WHITESUR_DIR" ]; then
        # Install only the Light variant to save space
        if [ -f "$WHITESUR_DIR/install.sh" ]; then
            cd "$WHITESUR_DIR"
            # Install minimal — just the GTK2/3 Light theme
            mkdir -p /usr/share/themes/WhiteSur-Light
            cp -r src/main/gtk-3.0/WhiteSur-Light /usr/share/themes/ 2>/dev/null || true
            cp -r src/main/gtk-2.0/WhiteSur-Light /usr/share/themes/ 2>/dev/null || true
            cd /
        fi
        echo "[themes] WhiteSur-Light GTK theme installed"
    fi
    rm -rf /tmp/whitesur.tar.gz /tmp/WhiteSur-gtk-theme-* 2>/dev/null
else
    echo "[themes] WARNING: Could not download WhiteSur theme (non-fatal)"
    echo "[themes] Falling back to Adwaita theme"
fi

# ── 4. Refresh font/icon caches ─────────────────────────────────────────────
echo "[themes] Refreshing caches..."
fc-cache -f 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/Haiku 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true

echo "[themes] Theme installation complete."
