# ============================================================================
# SuperLite OS — Desktop Package Group
# Wayland compositor (LabWC), status bar, terminal, notifications, launcher
# ============================================================================

SUMMARY = "SuperLite OS Wayland desktop environment"
DESCRIPTION = "LabWC compositor, Waybar, Foot terminal, Mako notifications, Tofi launcher, PipeWire audio"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    labwc \
    waybar \
    foot \
    mako \
    tofi \
    swaybg \
    swayidle \
    brightnessctl \
    gammastep \
    gsettings-desktop-schemas \
    seatd \
    mesa-dri \
    mesa-egl \
    mesa-gbm \
    libglvnd \
    libinput \
    libxkbcommon \
    wayland \
    wayland-protocols \
    xwayland \
    pipewire \
    wireplumber \
    pipewire-pulseaudio \
    pipewire-alsa \
    font-awesome \
    font-terminus \
    fonts-noto \
    fonts-noto-emoji \
    simp1e-cursors \
"
