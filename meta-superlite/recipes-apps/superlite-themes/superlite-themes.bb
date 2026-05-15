# ============================================================================
# SuperLite OS — Themes Recipe
# External themes: WhiteSur, Haiku icons, OhSnap font
# ============================================================================

SUMMARY = "SuperLite OS external themes"
DESCRIPTION = "WhiteSur GTK/icon theme, Haiku icons, OhSnap font for LabWC desktop"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "git://github.com/kelvinzer0/superlite-os.git;protocol=https;branch=main"
SRCREV = "${AUTOREV}"

S = "${WORKDIR}/git"

do_install() {
    install -d ${D}${datadir}/superlite/themes

    # Install pre-built theme archives
    if [ -d ${S}/alpine/packages/themes ]; then
        cp ${S}/alpine/packages/themes/* ${D}${datadir}/superlite/themes/ 2>/dev/null || true
    fi

    # Install theme installer script
    if [ -f ${S}/alpine/scripts/install-themes.sh ]; then
        install -m 0755 ${S}/alpine/scripts/install-themes.sh ${D}${datadir}/superlite/themes/install-themes.sh
    fi
}

FILES:${PN} = "${datadir}/superlite/themes"

RDEPENDS:${PN} = " \
    tar \
    gzip \
    unzip \
"
