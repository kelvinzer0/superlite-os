#!/usr/bin/env bash
# ============================================================================
# SuperLite OS — Build Script
# Builds a bootable hybrid ISO (UEFI + Legacy BIOS) from Alpine Linux edge
# with a LabWC Wayland desktop environment.
#
# Usage: ./build.sh [OPTIONS]
#   --clean      Remove build artifacts before building
#   --no-efi     Skip EFI boot support (Legacy BIOS only)
#   --verbose    Show detailed build output
#   --help       Show this help message
#
# Requirements (Debian/Ubuntu host):
#   sudo apt install squashfs-tools xorriso mtools dosfstools \
#     qemu-user-static binfmt-support wget ca-certificates
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ISO_DIR="${SCRIPT_DIR}/iso"
OUTPUT_DIR="${SCRIPT_DIR}"

ALPINE_VERSION="3.21"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
MINIROOTFS_URL="${ALPINE_MIRROR}/v${ALPINE_VERSION}/releases/x86_64/alpine-minirootfs-${ALPINE_VERSION}.3-x86_64.tar.gz"
MINIROOTFS_CACHE="${BUILD_DIR}/alpine-minirootfs.tar.gz"

PACKAGES_LIST="${SCRIPT_DIR}/alpine/configs/packages.list"
REPOS_FILE="${SCRIPT_DIR}/alpine/configs/repositories"
SETUP_SCRIPT="${SCRIPT_DIR}/alpine/scripts/setup-rootfs.sh"
DOTFILES_DIR="${SCRIPT_DIR}/dotfiles"

VERSION="$(date +%Y%m%d)"
ISO_NAME="superlite-os-${VERSION}.iso"

# Flags
CLEAN=false
NO_EFI=false
VERBOSE=false

# ---------------------------------------------------------------------------
# Colors & logging
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }
log_debug() { [[ "$VERBOSE" == true ]] && echo -e "[DEBUG] $*" || true; }

die() { log_error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)   CLEAN=true; shift ;;
        --no-efi)  NO_EFI=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --help)
            head -20 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *) die "Unknown option: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
check_deps() {
    local missing=()
    for cmd in mksquashfs wget tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Check for xorriso or mkisofs
    if ! command -v xorriso &>/dev/null && ! command -v mkisofs &>/dev/null; then
        missing+=("xorriso")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing dependencies: ${missing[*]}\nInstall with: sudo apt install squashfs-tools xorriso mtools dosfstools qemu-user-static binfmt-support wget"
    fi

    # Check root for chroot operations
    if [[ $EUID -ne 0 ]]; then
        log_warn "Not running as root. Will use sudo for chroot operations."
    fi
}

# ---------------------------------------------------------------------------
# Step 1: Download Alpine minirootfs
# ---------------------------------------------------------------------------
download_rootfs() {
    log_step "Downloading Alpine Linux minirootfs..."

    if [[ -f "$MINIROOTFS_CACHE" ]]; then
        log_info "Using cached minirootfs: ${MINIROOTFS_CACHE}"
        return 0
    fi

    mkdir -p "$BUILD_DIR"
    wget -q --show-progress -O "$MINIROOTFS_CACHE" "$MINIROOTFS_URL" \
        || die "Failed to download minirootfs from ${MINIROOTFS_URL}"

    log_info "Downloaded minirootfs to ${MINIROOTFS_CACHE}"
}

# ---------------------------------------------------------------------------
# Step 2: Create chroot rootfs
# ---------------------------------------------------------------------------
create_rootfs() {
    log_step "Creating Alpine rootfs..."

    # Clean previous rootfs
    [[ -d "$ROOTFS_DIR" ]] && rm -rf "$ROOTFS_DIR"
    mkdir -p "$ROOTFS_DIR"

    # Extract minirootfs
    log_info "Extracting minirootfs..."
    tar -xzf "$MINIROOTFS_CACHE" -C "$ROOTFS_DIR"

    # Mount required filesystems for chroot
    log_info "Mounting virtual filesystems..."
    mount --bind /dev     "${ROOTFS_DIR}/dev"     2>/dev/null || true
    mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    mount --bind /proc    "${ROOTFS_DIR}/proc"    2>/dev/null || true
    mount --bind /sys     "${ROOTFS_DIR}/sys"     2>/dev/null || true

    # Copy resolv.conf for DNS
    cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"

    # Copy QEMU static binary for cross-arch chroot (if available)
    if [[ -f /usr/bin/qemu-x86_64-static ]]; then
        cp /usr/bin/qemu-x86_64-static "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
    fi

    log_info "Rootfs created at ${ROOTFS_DIR}"
}

# ---------------------------------------------------------------------------
# Step 3: Configure and install packages inside chroot
# ---------------------------------------------------------------------------
configure_rootfs() {
    log_step "Configuring Alpine rootfs in chroot..."

    # Copy the setup script and configs into rootfs
    cp "$SETUP_SCRIPT"   "${ROOTFS_DIR}/tmp/setup-rootfs.sh"
    cp "$PACKAGES_LIST"  "${ROOTFS_DIR}/tmp/packages.list"
    cp "$REPOS_FILE"     "${ROOTFS_DIR}/tmp/repositories"
    chmod +x "${ROOTFS_DIR}/tmp/setup-rootfs.sh"

    # Copy dotfiles into rootfs for installation
    if [[ -d "$DOTFILES_DIR" ]]; then
        cp -r "$DOTFILES_DIR" "${ROOTFS_DIR}/tmp/dotfiles"
    fi

    # Copy hooks if they exist (includes firmware compression script)
    if [[ -d "${SCRIPT_DIR}/alpine/hooks" ]]; then
        cp -r "${SCRIPT_DIR}/alpine/hooks" "${ROOTFS_DIR}/tmp/hooks"
        # Also copy the firmware compression script
        if [[ -f "${SCRIPT_DIR}/alpine/scripts/compress-firmware.sh" ]]; then
            cp "${SCRIPT_DIR}/alpine/scripts/compress-firmware.sh" "${ROOTFS_DIR}/tmp/hooks/"
        fi
    fi

    # Copy theme installer script
    if [[ -f "${SCRIPT_DIR}/alpine/scripts/install-themes.sh" ]]; then
        mkdir -p "${ROOTFS_DIR}/tmp/hooks"
        cp "${SCRIPT_DIR}/alpine/scripts/install-themes.sh" "${ROOTFS_DIR}/tmp/hooks/"
    fi

    # Copy pre-built themes (WhiteSur, Haiku, OhSnap)
    if [[ -d "${SCRIPT_DIR}/alpine/packages/themes" ]]; then
        mkdir -p "${ROOTFS_DIR}/tmp/themes"
        cp "${SCRIPT_DIR}/alpine/packages/themes/"* "${ROOTFS_DIR}/tmp/themes/" 2>/dev/null || true
    fi

    # Copy mkinitfs config
    if [[ -f "${SCRIPT_DIR}/alpine/packages/mkinitfs-superlite.conf" ]]; then
        cp "${SCRIPT_DIR}/alpine/packages/mkinitfs-superlite.conf" "${ROOTFS_DIR}/tmp/hooks/"
    fi

    # Copy init patcher script (patches Alpine's init for live-boot support)
    if [[ -f "${SCRIPT_DIR}/alpine/scripts/patch-init.sh" ]]; then
        cp "${SCRIPT_DIR}/alpine/scripts/patch-init.sh" "${ROOTFS_DIR}/tmp/hooks/"
        chmod +x "${ROOTFS_DIR}/tmp/hooks/patch-init.sh"
    fi

    # Run setup inside chroot
    log_info "Running setup-rootfs.sh inside chroot (this may take a while)..."
    chroot "${ROOTFS_DIR}" /bin/sh /tmp/setup-rootfs.sh \
        || die "setup-rootfs.sh failed inside chroot"

    log_info "Rootfs configuration complete."
}

# ---------------------------------------------------------------------------
# Step 4: Build ISO
# ---------------------------------------------------------------------------
build_iso() {
    log_step "Building hybrid ISO..."

    # Delegate to make-iso.sh
    bash "${SCRIPT_DIR}/alpine/scripts/make-iso.sh" \
        --rootfs "$ROOTFS_DIR" \
        --iso-dir "$ISO_DIR" \
        --output "${OUTPUT_DIR}/${ISO_NAME}" \
        --version "$VERSION" \
        $( [[ "$NO_EFI" == true ]] && echo "--no-efi" ) \
        $( [[ "$VERBOSE" == true ]] && echo "--verbose" )

    local iso_size
    iso_size=$(du -sh "${OUTPUT_DIR}/${ISO_NAME}" | cut -f1)
    log_info "ISO created: ${OUTPUT_DIR}/${ISO_NAME} (${iso_size})"
}

# ---------------------------------------------------------------------------
# Step 5: Cleanup
# ---------------------------------------------------------------------------
cleanup() {
    log_step "Cleaning up mount points..."

    # Unmount chroot filesystems
    umount "${ROOTFS_DIR}/sys"     2>/dev/null || true
    umount "${ROOTFS_DIR}/proc"    2>/dev/null || true
    umount "${ROOTFS_DIR}/dev/pts" 2>/dev/null || true
    umount "${ROOTFS_DIR}/dev"     2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║         SuperLite OS Build System            ║"
    echo "║     Alpine Linux + LabWC Wayland Desktop     ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    # Clean if requested
    if [[ "$CLEAN" == true ]]; then
        log_info "Cleaning build directory..."
        cleanup
        rm -rf "$BUILD_DIR"
    fi

    # Trap for cleanup on exit
    trap cleanup EXIT

    check_deps
    download_rootfs
    create_rootfs
    configure_rootfs
    build_iso

    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "Build complete!"
    log_info "ISO: ${OUTPUT_DIR}/${ISO_NAME}"
    log_info ""
    log_info "Test with QEMU:"
    log_info "  qemu-system-x86_64 -m 2048 -cdrom ${ISO_NAME} -boot d"
    log_info ""
    log_info "Write to USB:"
    log_info "  sudo dd if=${ISO_NAME} of=/dev/sdX bs=4M status=progress"
    log_info "═══════════════════════════════════════════════"
}

main "$@"
