# ============================================================================
# SuperLite OS — swayidle Recipe
# Idle management daemon for Wayland
# ============================================================================

SUMMARY = "swayidle — Idle management daemon for Wayland"
HOMEPAGE = "https://github.com/swaywm/swayidle"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=396832e4425ab1d690ee6be3f9fd9628"

SRC_URI = "git://github.com/swaywm/swayidle.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "1.8.0"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    wayland-native \
"

RDEPENDS:${PN} = "bash"

REQUIRED_DISTRO_FEATURES = "wayland"
