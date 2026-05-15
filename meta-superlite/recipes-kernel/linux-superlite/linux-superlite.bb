# ============================================================================
# SuperLite OS — Custom Kernel Recipe
# Based on linux-yocto, configured for live desktop with WiFi + GPU support
# ============================================================================

SUMMARY = "SuperLite OS Linux kernel"
DESCRIPTION = "Custom kernel with i915, amdgpu, ath10k, rtlwifi firmware and live-boot support"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

# Use linux-yocto as base
LINUX_VERSION = "6.12.28"
LINUX_VERSION_EXTENSION = "-superlite"

SRC_URI = "git://git.yoctoproject.org/linux-yocto.git;protocol=https;branch=6.12;name=machine \
           git://git.yoctoproject.org/yocto-kernel-cache;protocol=https;type=kmeta;name=meta;branch=yocto-6.12;destsuffix=kernel-meta"

SRCREV_machine = "${AUTOREV}"
SRCREV_meta = "${AUTOREV}"

PV = "${LINUX_VERSION}+git"

# Kernel config fragments
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-superlite:"

SRC_URI += " \
    file://superlite.cfg \
    file://gpu.cfg \
    file://wifi.cfg \
    file://live-boot.cfg \
"

# Extra firmware packages
RRECOMMENDS:${PN} += " \
    linux-firmware-i915 \
    linux-firmware-amdgpu \
    linux-firmware-ath10k \
    linux-firmware-rtlwifi \
    linux-firmware-rtw89 \
    linux-firmware-rtl-bt \
    linux-firmware-brcm \
    linux-firmware-cirrus \
"

COMPATIBLE_MACHINE = "superlite-x86_64"
