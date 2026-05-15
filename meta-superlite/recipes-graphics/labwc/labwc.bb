# ============================================================================
# SuperLite OS — LabWC Recipe
# Wayland compositor (openbox-like tiling/floating)
# ============================================================================

SUMMARY = "LabWC — Wayland compositor inspired by openbox"
DESCRIPTION = "Stacking Wayland compositor with tiling, suitable for lightweight desktops"
HOMEPAGE = "https://github.com/labwc/labwc"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=751419260aa954499f7abaabaa882bbe"

SRC_URI = "git://github.com/labwc/labwc.git;protocol=https;branch=main"
SRCREV = "${AUTOREV}"
PV = "0.8.3+git"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    libinput \
    libxkbcommon \
    cairo \
    pango \
    glib-2.0 \
    wlroots \
    librsvg \
    libxml2 \
    wayland-native \
"

RDEPENDS:${PN} = " \
    xwayland \
    swaybg \
"

REQUIRED_DISTRO_FEATURES = "wayland"

FILES:${PN} += " \
    ${datadir}/labwc \
    ${datadir}/wayland-sessions \
"
