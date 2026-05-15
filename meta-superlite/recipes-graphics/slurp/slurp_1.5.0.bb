# ============================================================================
# SuperLite OS — slurp Recipe
# Region selector for Wayland
# ============================================================================

SUMMARY = "slurp — Region selector for Wayland"
HOMEPAGE = "https://github.com/emersion/slurp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=396832e4425ab1d690ee6be3f9fd9628"

SRC_URI = "git://github.com/emersion/slurp.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "1.5.0"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    cairo \
    pango \
    libxkbcommon \
    wayland-native \
"

REQUIRED_DISTRO_FEATURES = "wayland"
