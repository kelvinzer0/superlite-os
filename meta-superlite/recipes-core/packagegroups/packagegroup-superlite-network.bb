# ============================================================================
# SuperLite OS — Network Package Group
# WiFi, wired, Bluetooth networking stack
# ============================================================================

SUMMARY = "SuperLite OS networking packages"
DESCRIPTION = "NetworkManager, WiFi, Bluetooth, and network utilities"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    networkmanager \
    networkmanager-nmcli \
    networkmanager-wifi \
    wpa-supplicant \
    iw \
    wireless-regdb \
    bluez5 \
    bluez5-noinst-tools \
    iptables \
    iproute2 \
    iputils \
    dhcpcd \
    nss \
"
