# ============================================================================
# SuperLite OS — Core Image Recipe
# Bootable live desktop ISO with LabWC Wayland compositor
# ============================================================================

SUMMARY = "SuperLite OS — Ultra-lightweight Alpine Linux desktop"
DESCRIPTION = "Alpine Linux edge with LabWC Wayland compositor. Boots from USB, runs entirely in RAM. ~400MB ISO."
HOMEPAGE = "https://github.com/kelvinzer0/superlite-os"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image extrausers

# ── Image Features ──────────────────────────────────────────────────────────
IMAGE_FEATURES += " \
    ssh-server-openssh \
    package-management \
    debug-tweaks \
    hwcodecs \
"

IMAGE_LINGUAS = "en-us"

# ── Package Groups ──────────────────────────────────────────────────────────
CORE_IMAGE_EXTRA_INSTALL += " \
    packagegroup-superlite-base \
    packagegroup-superlite-desktop \
    packagegroup-superlite-network \
    packagegroup-superlite-apps \
    superlite-live \
    superlite-dotfiles \
    superlite-hooks \
    superlite-themes \
"

# ── Extra packages not in packagegroups ─────────────────────────────────────
CORE_IMAGE_EXTRA_INSTALL += " \
    alpine-base-busybox \
    openrc \
"

# ── Root password (live user) ──────────────────────────────────────────────
EXTRA_USERS_PARAMS = " \
    useradd -d /home/live -s /bin/bash -G wheel live; \
    usermod -p '\$6\$rounds=656000\$randomsalt\$hashedpw' live; \
    usermod -p '' root; \
"

# ── Image postprocess — live-boot specific setup ────────────────────────────
rootfs_live_install() {
    # Install live-boot hooks (mkinitfs, live init, etc.)
    install -d ${IMAGE_ROOTFS}/etc/mkinitfs/features.d
    install -d ${IMAGE_ROOTFS}/etc/mkinitfs
    install -d ${IMAGE_ROOTFS}/usr/share/superlite

    # Version info
    echo "SuperLite OS ${DISTRO_VERSION}" > ${IMAGE_ROOTFS}/usr/share/superlite/version.txt
    echo "Build: $(date +%Y%m%d)" >> ${IMAGE_ROOTFS}/usr/share/superlite/version.txt

    # Hostname
    echo "superlite" > ${IMAGE_ROOTFS}/etc/hostname

    # MOTD
    cat > ${IMAGE_ROOTFS}/etc/motd << 'MOTD'

  ╔══════════════════════════════════════╗
  ║      ⚡ SuperLite OS                 ║
  ║   Alpine Linux + LabWC Wayland       ║
  ╚══════════════════════════════════════╝

MOTD

    # fstab for live boot
    cat > ${IMAGE_ROOTFS}/etc/fstab << 'FSTAB'
proc            /proc    proc     defaults              0 0
sysfs           /sys     sysfs    defaults              0 0
devtmpfs        /dev     devtmpfs defaults              0 0
tmpfs           /tmp     tmpfs    defaults,noatime      0 0
tmpfs           /run     tmpfs    defaults,noatime      0 0
FSTAB

    # NetworkManager config
    install -d ${IMAGE_ROOTFS}/etc/NetworkManager
    cat > ${IMAGE_ROOTFS}/etc/NetworkManager/NetworkManager.conf << 'NM'
[main]
plugins=ifupdown,keyfile
dhcp=internal

[ifupdown]
managed=false

[device]
wifi.backend=wpa_supplicant
NM

    # Auto-login on tty1
    install -d ${IMAGE_ROOTFS}/etc/systemd/system/getty@tty1.service.d
    cat > ${IMAGE_ROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 115200 linux
AUTOLOGIN

    # XDG / Wayland environment
    install -d ${IMAGE_ROOTFS}/etc/profile.d
    cat > ${IMAGE_ROOTFS}/etc/profile.d/xdg.sh << 'XDG'
export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
mkdir -pm 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
export XDG_RUNTIME_DIR
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export GDK_BACKEND=wayland,x11
XDG
    chmod 0755 ${IMAGE_ROOTFS}/etc/profile.d/xdg.sh

    # Sudoers for live user
    install -d ${IMAGE_ROOTFS}/etc/sudoers.d
    echo "live ALL=(ALL) NOPASSWD: ALL" > ${IMAGE_ROOTFS}/etc/sudoers.d/live
    chmod 0440 ${IMAGE_ROOTFS}/etc/sudoers.d/live

    # Strip binaries and remove docs to minimize image size
    find ${IMAGE_ROOTFS}/usr/lib -name "*.so*" -type f -exec ${HOST_PREFIX}strip --strip-unneeded {} \; 2>/dev/null || true
    find ${IMAGE_ROOTFS}/usr/bin ${IMAGE_ROOTFS}/usr/sbin -type f -exec ${HOST_PREFIX}strip --strip-unneeded {} \; 2>/dev/null || true
    rm -rf ${IMAGE_ROOTFS}/usr/share/man ${IMAGE_ROOTFS}/usr/share/doc
    rm -rf ${IMAGE_ROOTFS}/usr/share/help ${IMAGE_ROOTFS}/usr/share/gtk-doc
    rm -rf ${IMAGE_ROOTFS}/usr/share/i18n ${IMAGE_ROOTFS}/usr/share/locale/*
    rm -rf ${IMAGE_ROOTFS}/usr/lib/pkgconfig ${IMAGE_ROOTFS}/usr/lib/cmake
    rm -rf ${IMAGE_ROOTFS}/usr/include
    rm -rf ${IMAGE_ROOTFS}/usr/share/pkgconfig
}

ROOTFS_POSTPROCESS_COMMAND += "rootfs_live_install;"

# ── Image size constraint ──────────────────────────────────────────────────
IMAGE_ROOTFS_SIZE = "800000"
IMAGE_ROOTFS_MAXSIZE = "900000"
