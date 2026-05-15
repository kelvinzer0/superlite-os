# ============================================================================
# SuperLite OS — grim Recipe
# Screenshot tool for Wayland
# ============================================================================

SUMMARY = "grim — Screenshot tool for Wayland"
HOMEPAGE = "https://github.com/emersion/grim"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=396832e4425ab1d690ee6be3f9fd9628"

SRC_URI = "git://github.com/emersion/grim.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "1.4.1"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    cairo \
    libjpeg-turbo \
    libpng \
    pixman \
    libxkbcommon \
    wayland-native \
"

REQUIRED_DISTRO_FEATURES = "wayland"
