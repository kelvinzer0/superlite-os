# ============================================================================
# SuperLite OS — Dotfiles Recipe
# Installs LabWC, Waybar, Foot, Mako, Tofi, and shell configs
# ============================================================================

SUMMARY = "SuperLite OS desktop configuration files"
DESCRIPTION = "Dotfiles for LabWC, Waybar, Foot terminal, Mako, Tofi, and shell profiles"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Source is the dotfiles directory from the repo
SRC_URI = "git://github.com/kelvinzer0/superlite-os.git;protocol=https;branch=main"
SRCREV = "${AUTOREV}"

S = "${WORKDIR}/git"

do_install() {
    # Install dotfiles to /etc/skel (template for new users)
    install -d ${D}${sysconfdir}/skel

    # Copy all dotfiles preserving structure
    cp -rT ${S}/dotfiles ${D}${sysconfdir}/skel/ 2>/dev/null || \
        cp -r ${S}/dotfiles/. ${D}${sysconfdir}/skel/

    # Ensure scripts are executable
    find ${D}${sysconfdir}/skel -name '*.sh' -exec chmod 0755 {} \; 2>/dev/null || true
    chmod 0755 ${D}${sysconfdir}/skel/.config/scripts/* 2>/dev/null || true

    # Also install to /root for root auto-login
    install -d ${D}/root
    cp -rT ${S}/dotfiles ${D}/root/ 2>/dev/null || \
        cp -r ${S}/dotfiles/. ${D}/root/
    find ${D}/root -name '*.sh' -exec chmod 0755 {} \; 2>/dev/null || true
    chmod 0755 ${D}/root/.config/scripts/* 2>/dev/null || true

    # Root auto-start LabWC profile
    cat > ${D}/root/.profile << 'ROOTPROFILE'
# SuperLite OS — root profile
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wlroots
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11

# Auto-start LabWC on tty1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec labwc
fi
ROOTPROFILE
}

FILES:${PN} = " \
    ${sysconfdir}/skel \
    /root/.profile \
    /root/.bashrc \
    /root/.config \
"

# Prevent parallel install conflicts
PARALLEL_MAKEINST = ""
