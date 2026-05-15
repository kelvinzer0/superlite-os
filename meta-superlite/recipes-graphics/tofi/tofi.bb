# ============================================================================
# SuperLite OS — Tofi Recipe
# Rofi-style application launcher for Wayland
# ============================================================================

SUMMARY = "Tofi — Wayland application launcher (rofi-style)"
HOMEPAGE = "https://github.com/philj56/tofi"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=aeaa99dbb0c0f13ab0a1e5e0b5a7f5e7"

SRC_URI = "git://github.com/philj56/tofi.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "0.9.1+git"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    freetype \
    fontconfig \
    cairo \
    pango \
    harfbuzz \
    libxkbcommon \
    wayland-native \
"

REQUIRED_DISTRO_FEATURES = "wayland"
