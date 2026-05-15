# ============================================================================
# SuperLite OS — Applications Package Group
# System utilities and tools
# ============================================================================

SUMMARY = "SuperLite OS desktop applications"
DESCRIPTION = "System utilities and tools"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    vim \
    jq \
    htop \
    tree \
    unzip \
    rsync \
"
