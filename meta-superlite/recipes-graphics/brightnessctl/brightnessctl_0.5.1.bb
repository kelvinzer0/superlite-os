# ============================================================================
# SuperLite OS — brightnessctl Recipe
# Backlight brightness control
# ============================================================================

SUMMARY = "brightnessctl — Backlight brightness control"
HOMEPAGE = "https://github.com/Hummer12007/brightnessctl"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=396832e4425ab1d690ee6be3f9fd9628"

SRC_URI = "git://github.com/Hummer12007/brightnessctl.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PV = "0.5.1"

S = "${WORKDIR}/git"

# brightnessctl uses a simple Makefile
do_compile() {
    oe_runmake
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/brightnessctl ${D}${bindir}/
}
