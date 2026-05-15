# ============================================================================
# SuperLite OS — Base Package Group
# Core system: kernel, init, shell, essential utils
# ============================================================================

SUMMARY = "SuperLite OS base system packages"
DESCRIPTION = "Minimal base system with busybox, openrc, kernel modules, and essential utilities"
LICENSE = "MIT"

inherit packagegroup

RDEPENDS:${PN} = " \
    busybox \
    busybox-suid \
    busybox-extras \
    kmod \
    util-linux \
    util-linux-mount \
    util-linux-umount \
    e2fsprogs-mke2fs \
    e2fsprogs-e2fsck \
    dosfstools \
    squashfs-tools \
    mtools \
    syslinux \
    xorriso \
    lua \
    shadow \
    shadow-base \
    sudo \
    bash \
    coreutils \
    procps \
    psmisc \
    grep \
    sed \
    gawk \
    findutils \
    gzip \
    bzip2 \
    xz \
    tar \
    wget \
    curl \
    ca-certificates \
    chrony \
    tlp \
    openssh \
    dbus \
"
