# ============================================================================
# SuperLite OS — Waybar Recipe
# Highly customizable Wayland bar for Sway and Wlroots-based compositors
# ============================================================================

SUMMARY = "Waybar — Wayland bar with workspaces, clock, system tray"
HOMEPAGE = "https://github.com/Alexays/Waybar"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=58a3ae03e2e3f2a3a4c8e4d1b6e3e3e3"

SRC_URI = "git://github.com/Alexays/Waybar.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "0.11.0+git"

S = "${WORKDIR}/git"

inherit meson pkgconfig features_check

DEPENDS = " \
    wayland \
    wayland-protocols \
    wlroots \
    gtkmm-3.0 \
    jsoncpp \
    libinput \
    libsigc-2.0 \
    fmt \
    spdlog \
    gtk-layer-shell \
    libnl \
    upower \
    pulseaudio \
    wireplumber \
"

REQUIRED_DISTRO_FEATURES = "wayland"

FILES:${PN} += "${datadir}/waybar"
