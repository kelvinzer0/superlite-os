# ============================================================================
# SuperLite OS — Alpine mkimage profile
# Replaces Yocto entirely. Alpine's native ISO builder.
# ============================================================================

profile_superlite() {
    profile_virt

    kernel_cmdline="unionfs_size=512M console=tty0 console=ttyS0,115200"
    initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,iso9660,vfat,nls_cp437,nls_iso8859_1 quiet"
    syslinux_serial="0 115200"

    apks="$apks
        alpine-base openrc busybox busybox-suid busybox-static busybox-extras kmod
        linux-lts linux-virt
        linux-firmware-i915 linux-firmware-amdgpu linux-firmware-amd-ucode
        linux-firmware-ath10k linux-firmware-rtlwifi linux-firmware-rtw89
        linux-firmware-rtl_bt linux-firmware-brcm linux-firmware-cirrus linux-firmware-other
        labwc foot mesa-dri-gallium mesa-egl mesa-gl mesa-gbm seatd dbus
        waybar swaybg swayidle mako tofi gammastep brightnessctl
        gsettings-desktop-schemas
        font-awesome font-terminus simp1e-cursors
        networkmanager
        grub-efi grub-bios syslinux squashfs-tools xorriso mkinitfs mtools dosfstools lua5.4
        dbus-x11
        sudo
    "

    apkovl="genapkovl-superlite.sh"

    #kernel_flavors="lts"
}
