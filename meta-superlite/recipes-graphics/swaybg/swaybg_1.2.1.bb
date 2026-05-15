# ============================================================================
# SuperLite OS — swaybg Recipe
# Wallpaper tool for Wayland compositors
# ============================================================================

SUMMARY = "swaybg — Wallpaper tool for Wayland"
HOMEPAGE = "https://github.com/swaywm/swaybg"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=396832e4425ab1d690ee6be3f9fd9628"

SRC_URI = "git://github.com/swaywm/swaybg.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "1.2.1"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    cairo \
    gdk-pixbuf \
    libxkbcommon \
    wayland-native \
"

REQUIRED_DISTRO_FEATURES = "wayland"
