# ============================================================================
# SuperLite OS — Alpine mkimage profile
# Replaces Yocto entirely. Alpine's native ISO builder.
# ============================================================================

profile_superlite() {
    profile_virt

    kernel_cmdline="unionfs_size=0 console=tty0 console=ttyS0,115200"
    initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,iso9660,vfat,nls_cp437,nls_iso8859_1 quiet"
    syslinux_serial="0 115200"
    modloop_sign=no

    # Read repos from alpine/configs/repositories
    local _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local _configs_dir="$_script_dir/../../alpine/configs"
    repos="$repos $(cat "$_configs_dir/repositories" | tr '\n' ' ')"

    # Exclude conflicting vlan package (breaks ifupdown-ng in edge)
    apks="$apks !vlan"

    # Read packages from alpine/configs/packages.list
    apks="$apks $(sed 's/#.*//;/^[[:space:]]*$/d' "$_configs_dir/packages.list" | tr '\n' ' ')"

    apkovl="genapkovl-superlite.sh"

    kernel_flavors="lts"
    kernel_addons=""
}
