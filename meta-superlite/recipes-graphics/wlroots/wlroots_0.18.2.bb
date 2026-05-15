# ============================================================================
# SuperLite OS — wlroots Recipe
# Modular Wayland compositor library
# ============================================================================

SUMMARY = "wlroots — Modular Wayland compositor library"
DESCRIPTION = "A modular Wayland compositor library providing building blocks for Wayland compositors"
HOMEPAGE = "https://gitlab.freedesktop.org/wlroots/wlroots"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=396832e4425ab1d690ee6be3f9fd9628"

SRC_URI = "git://gitlab.freedesktop.org/wlroots/wlroots.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "0.18.2"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    libinput \
    libxkbcommon \
    pixman \
    libdrm \
    mesa \
    udev \
    seatd \
    hwdata \
    wayland-native \
"

PACKAGECONFIG ?= "drm libinput backend-drm"
PACKAGECONFIG[drm] = "-Ddrm=enabled,-Ddrm=disabled"
PACKAGECONFIG[libinput] = "-Dlibinput_backend=enabled,-Dlibinput_backend=disabled"
PACKAGECONFIG[x11] = "-Dx11_backend=enabled,-Dx11_backend=disabled"
PACKAGECONFIG[xwayland] = "-Dxwayland=enabled,-Dxwayland=disabled"

REQUIRED_DISTRO_FEATURES = "wayland"

FILES:${PN} += "${libdir}/libwlroots*.so*"
FILES:${PN}-dev += "${libdir}/pkgconfig ${includedir}"
