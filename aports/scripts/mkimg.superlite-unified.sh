# ============================================================================
# SuperLite OS — Unified ISO Profile
# Single ISO with boot menu: Desktop / Install / Partition Manager
# ============================================================================

profile_superlite-unified() {
    profile_virt

    kernel_cmdline="unionfs_size=0 console=tty0 console=ttyS0,115200"
    initfs_cmdline="modules=loop,squashfs,sd-mod,usb-storage,iso9660,vfat,nls_cp437,nls_iso8859_1 quiet"
    syslinux_serial="0 115200"
    modloop_sign=no

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

    # Unified: include ALL packages from desktop + install + parted
    # Deduplicate and merge
    _merge_packages() {
        for f in "$_configs_dir/packages.list" "$_configs_dir/packages-install.list" "$_configs_dir/packages-parted.list"; do
            [ -f "$f" ] && sed '/# --- Boot (ISO only/,$d; s/#.*//; /^[[:space:]]*$/d' "$f"
        done | sort -u | tr '\n' ' '
    }

    apks="$apks $(_merge_packages)"

    apkovl="genapkovl-superlite-unified.sh"

    kernel_flavors="lts"
    kernel_addons=""
}
