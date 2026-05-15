# ============================================================================
# SuperLite OS — Hooks Recipe
# Feature hooks for mkinitfs and system customization
# ============================================================================

SUMMARY = "SuperLite OS system hooks"
DESCRIPTION = "mkinitfs feature hooks, init wrappers, and system customization scripts"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "git://github.com/kelvinzer0/superlite-os.git;protocol=https;branch=main"
SRCREV = "${AUTOREV}"

S = "${WORKDIR}/git"

do_install() {
    install -d ${D}${datadir}/superlite/hooks

    # Install all hook scripts
    if [ -d ${S}/alpine/hooks ]; then
        cp -r ${S}/alpine/hooks/* ${D}${datadir}/superlite/hooks/
    fi

    # Install scripts
    if [ -d ${S}/alpine/scripts ]; then
        install -m 0755 ${S}/alpine/scripts/setup-rootfs.sh ${D}${datadir}/superlite/hooks/ 2>/dev/null || true
        install -m 0755 ${S}/alpine/scripts/make-iso.sh ${D}${datadir}/superlite/hooks/ 2>/dev/null || true
        install -m 0755 ${S}/alpine/scripts/install-themes.sh ${D}${datadir}/superlite/hooks/ 2>/dev/null || true
        install -m 0755 ${S}/alpine/scripts/compress-firmware.sh ${D}${datadir}/superlite/hooks/ 2>/dev/null || true
    fi

    find ${D}${datadir}/superlite/hooks -type f -exec chmod 0755 {} \;
}

FILES:${PN} = "${datadir}/superlite/hooks"
