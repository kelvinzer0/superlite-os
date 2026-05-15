# ============================================================================
# SuperLite OS — Mako Recipe
# Lightweight Wayland notification daemon
# ============================================================================

SUMMARY = "Mako — Lightweight Wayland notification daemon"
HOMEPAGE = "https://github.com/emersion/mako"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=396832e4425ab1d690ee6be3f9fd9628"

SRC_URI = "git://github.com/emersion/mako.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "1.9.0"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    pango \
    cairo \
    glib-2.0 \
    libxkbcommon \
    wayland-native \
"

REQUIRED_DISTRO_FEATURES = "wayland"
