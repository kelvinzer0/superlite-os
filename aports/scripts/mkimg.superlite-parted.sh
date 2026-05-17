# ============================================================================
# SuperLite OS — Disk Partition Management ISO Profile
# Minimal bootable environment for partition CRUD
# ============================================================================

profile_superlite-parted() {
    profile_virt

    kernel_cmdline="unionfs_size=0 console=tty0 console=ttyS0,115200"
    initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,iso9660,vfat,nls_cp437,nls_iso8859_1 quiet"
    syslinux_serial="0 115200"
    modloop_sign=no

    # Find configs directory
    _configs_dir=""
    for dir in \
        "$(cd "$(dirname "$0")" && pwd)/alpine/configs" \
        "/build/alpine/configs" \
        "./alpine/configs" \
        "$(cd "$(dirname "$0")" && pwd)/../../alpine/configs"; do
        if [ -d "$dir" ] && [ -f "$dir/repositories" ]; then
            _configs_dir="$dir"
            break
        fi
    done

    if [ -z "$_configs_dir" ]; then
        echo "ERROR: alpine/configs directory not found" >&2
        exit 1
    fi

    repos="$repos $(cat "$_configs_dir/repositories" | tr '\n' ' ')"
    apks="$apks !vlan"

    # Use partition tools package list
    apks="$apks $(sed 's/#.*//;/^[[:space:]]*$/d' "$_configs_dir/packages-parted.list" | tr '\n' ' ')"

    apkovl="genapkovl-superlite-parted.sh"

    kernel_flavors="lts"
    kernel_addons=""
}
