# ============================================================================
# SuperLite OS — Live Boot Recipe
# Installs mkinitfs hooks, Lua live init, and live-boot scripts
# ============================================================================

SUMMARY = "SuperLite OS live-boot support"
DESCRIPTION = "mkinitfs feature hooks, Lua-based live init, and live-boot configuration"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Local source — uses files from the layer itself
SRC_URI = " \
    file://mkinitfs-superlite.conf \
    file://superlite-live \
    file://superlite-live.init \
    file://superlite-init-wrapper \
    file://compress-firmware.sh \
    file://superlite-boot.sh \
"

S = "${WORKDIR}"

do_install() {
    # mkinitfs configuration
    install -d ${D}${sysconfdir}/mkinitfs/features.d
    install -d ${D}${sysconfdir}/mkinitfs

    install -m 0644 ${WORKDIR}/mkinitfs-superlite.conf ${D}${sysconfdir}/mkinitfs/superlite.conf
    install -m 0755 ${WORKDIR}/superlite-live ${D}${sysconfdir}/mkinitfs/features.d/superlite-live

    # Live init (Lua script for initramfs)
    install -d ${D}${datadir}/superlite
    install -m 0755 ${WORKDIR}/superlite-live.init ${D}${datadir}/superlite/superlite-live.init
    install -m 0755 ${WORKDIR}/superlite-init-wrapper ${D}${datadir}/superlite/superlite-init-wrapper

    # Firmware compression script
    install -m 0755 ${WORKDIR}/compress-firmware.sh ${D}${datadir}/superlite/compress-firmware.sh

    # Boot script (ISO generation helper)
    install -m 0755 ${WORKDIR}/superlite-boot.sh ${D}${bindir}/superlite-boot
}

FILES:${PN} = " \
    ${sysconfdir}/mkinitfs \
    ${datadir}/superlite \
    ${bindir}/superlite-boot \
"

RDEPENDS:${PN} = " \
    mkinitfs \
    lua \
    squashfs-tools \
    busybox \
"
