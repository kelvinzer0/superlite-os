# ============================================================================
# SuperLite OS — Installation ISO Profile
# Full desktop + disk partitioning + installer
# ============================================================================

profile_superlite-install() {
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

    # Use installation package list
    apks="$apks $(sed 's/#.*//;/^[[:space:]]*$/d' "$_configs_dir/packages-install.list" | tr '\n' ' ')"

    apkovl="genapkovl-superlite-install.sh"

    kernel_flavors="lts"
    kernel_addons=""
}
