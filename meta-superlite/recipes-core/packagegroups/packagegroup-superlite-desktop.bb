# ============================================================================
# SuperLite OS — Desktop Package Group
# Wayland compositor (LabWC), status bar, terminal, notifications, launcher
# ============================================================================

SUMMARY = "SuperLite OS Wayland desktop environment"
DESCRIPTION = "LabWC compositor, Waybar, Mako notifications, Tofi launcher, PipeWire audio"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    labwc \
    waybar \
    mako \
    tofi \
    swaybg \
    swayidle \
    brightnessctl \
    seatd \
    mesa \
    libinput \
    libxkbcommon \
    wayland \
    wayland-protocols \
    pipewire \
    wireplumber \
    cantarell-fonts \
    liberation-fonts \
    ttf-bitstream-vera \
"
