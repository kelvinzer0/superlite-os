# ============================================================================
# SuperLite OS — Applications Package Group
# File manager, editor, browser, screenshot tools
# ============================================================================

SUMMARY = "SuperLite OS desktop applications"
DESCRIPTION = "PCManFM, Micro, Neovim, Firefox, Grim+Slurp screenshots"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    pcmanfm \
    micro \
    neovim \
    firefox \
    grim \
    slurp \
    jq \
    htop \
    tree \
    unzip \
    rsync \
"
