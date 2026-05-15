# ============================================================================
# SuperLite OS — Foot Recipe
# Fast, lightweight Wayland terminal emulator
# ============================================================================

SUMMARY = "Foot — Wayland-native terminal emulator"
HOMEPAGE = "https://codeberg.org/dnkl/foot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=8264ef4b6b0d0eacd0a2e7bfc2fe1a67"

SRC_URI = "git://codeberg.org/dnkl/foot.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "1.17.2+git"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    fontconfig \
    freetype \
    pixman \
    libxkbcommon \
    tllist \
    fcft \
    wayland-native \
    pixman-native \
    ncurses \
"

REQUIRED_DISTRO_FEATURES = "wayland"

FILES:${PN} += "${datadir}/foot"
