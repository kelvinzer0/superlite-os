#!/usr/bin/env bash
# ============================================================================
# SuperLite OS — Yocto Build Script
# Initializes Poky/OE-Core and builds the SuperLite OS image
#
# Usage: ./build.sh [OPTIONS]
#   --setup-only    Only set up the Yocto environment, don't build
#   --clean         Clean build artifacts before building
#   --bitbake-args  Extra args passed to bitbake
#   --help          Show help
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
POKY_DIR="${BUILD_DIR}/poky"
META_SUPERLITE="${SCRIPT_DIR}/meta-superlite"
MACHINE="superlite-x86_64"
DISTRO="superlite"
IMAGE="superlite-os-image"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }
die()       { log_error "$@"; exit 1; }

# ── Args ────────────────────────────────────────────────────────────────────
SETUP_ONLY=false
CLEAN=false
BITBAKE_ARGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup-only)   SETUP_ONLY=true; shift ;;
        --clean)        CLEAN=true; shift ;;
        --bitbake-args) BITBAKE_ARGS="$2"; shift 2 ;;
        --help)
            head -15 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *) die "Unknown option: $1" ;;
    esac
done

# ── Preflight ──────────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in git python3 tar gzip diffstat chrpath cpio wget; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -gt 0 ]] && die "Missing dependencies: ${missing[*]}\nInstall with: sudo apt install gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat cpio python3 python3-pip python3-pexpect python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales libacl1"

    # Check for xorriso (ISO generation)
    command -v xorriso &>/dev/null || log_warn "xorriso not found — ISO generation will fail. Install: sudo apt install xorriso"

    # Check for squashfs-tools
    command -v mksquashfs &>/dev/null || log_warn "squashfs-tools not found. Install: sudo apt install squashfs-tools"

    # Check locale
    locale -a 2>/dev/null | grep -qi "en_us.utf" || log_warn "en_US.UTF-8 locale not found — Yocto may fail. Run: sudo locale-gen en_US.UTF-8"
}

# ── Setup Poky ─────────────────────────────────────────────────────────────
setup_poky() {
    log_step "Setting up Poky (Yocto reference build system)..."

    mkdir -p "$BUILD_DIR"

    if [[ ! -d "$POKY_DIR" ]]; then
        log_info "Cloning Poky (scarthgap branch)..."
        git clone --depth 1 --branch scarthgap \
            https://git.yoctoproject.org/poky "$POKY_DIR"
    else
        log_info "Poky already present at ${POKY_DIR}"
    fi

    # Clone required layers
    local layers_dir="${POKY_DIR}/.."

    # meta-openembedded (for additional packages)
    if [[ ! -d "${layers_dir}/meta-openembedded" ]]; then
        log_info "Cloning meta-openembedded..."
        git clone --depth 1 --branch scarthgap \
            https://git.openembedded.org/meta-openembedded "${layers_dir}/meta-openembedded"
    fi

    # meta-alpine (for musl/Alpine packages — optional)
    if [[ ! -d "${layers_dir}/meta-alpine" ]]; then
        log_info "Cloning meta-alpine (optional, for musl support)..."
        git clone --depth 1 \
            https://github.com/agherzan/meta-alpine.git "${layers_dir}/meta-alpine" 2>/dev/null || \
            log_warn "meta-alpine not available — using glibc fallback"
    fi
}

# ── Configure build ────────────────────────────────────────────────────────
configure_build() {
    log_step "Configuring Yocto build..."

    local conf_dir="${BUILD_DIR}/conf"
    mkdir -p "$conf_dir"

    # bblayers.conf
    cat > "${conf_dir}/bblayers.conf" << EOF
# POKY_BBLAYERS_CONF_VERSION is increased each time build/conf/bblayers.conf
# changes incompatibly
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS = " \\
  ${POKY_DIR}/meta \\
  ${POKY_DIR}/meta-poky \\
  ${POKY_DIR}/meta-yocto-bsp \\
  ${BUILD_DIR}/../meta-openembedded/meta-oe \\
  ${BUILD_DIR}/../meta-openembedded/meta-python \\
  ${BUILD_DIR}/../meta-openembedded/meta-networking \\
  ${BUILD_DIR}/../meta-openembedded/meta-multimedia \\
  ${META_SUPERLITE} \\
"
EOF

    # Add meta-alpine if available
    if [[ -d "${BUILD_DIR}/../meta-alpine" ]]; then
        sed -i '/meta-multimedia/a\  ${TOPDIR}/../meta-alpine \\' "${conf_dir}/bblayers.conf"
    fi

    # local.conf
    cat > "${conf_dir}/local.conf" << EOF
# SuperLite OS — Yocto Build Configuration

MACHINE = "${MACHINE}"
DISTRO = "${DISTRO}"

# Package management
PACKAGE_CLASSES = "package_ipk"

# Parallel build
BB_NUMBER_THREADS = "\$(nproc)"
PARALLEL_MAKE = "-j \$(nproc)"

# Disk monitoring
BB_DISKMON_DIRS = "\\
    STOPTASKS,\${TMPDIR},1G,100K \\
    STOPTASKS,\${DL_DIR},1G,100K \\
    STOPTASKS,\${SSTATE_DIR},1G,100K \\
    ABORT,\${TMPDIR},100M,1K \\
    ABORT,\${DL_DIR},100M,1K \\
    ABORT,\${SSTATE_DIR},100M,1K"

# Download directory (shared across builds)
DL_DIR = "\${TOPDIR}/downloads"
SSTATE_DIR = "\${TOPDIR}/sstate-cache"

# Image type
IMAGE_FSTYPES = "squashfs-xz"

# Security — accept commercial licenses for firmware
LICENSE_FLAGS_ACCEPTED += "commercial"

# Enable kernel build
KERNEL_IMAGETYPE = "bzImage"

# Extra space for live image
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Debug — keep working directory for debugging
RM_WORK_EXCLUDE += "linux-superlite"

# Preserve build history
INHERIT += "buildhistory"
BUILDHISTORY_COMMIT = "1"
EOF

    log_info "Build configuration written to ${conf_dir}/"
}

# ── Build ──────────────────────────────────────────────────────────────────
build_image() {
    log_step "Initializing BitBake environment..."
    cd "$POKY_DIR"
    # oe-init-build-env uses unbound vars (BBSERVER, etc.) — relax strict mode
    set +u
    source oe-init-build-env "$BUILD_DIR"
    set -u

    if [[ "$SETUP_ONLY" == true ]]; then
        log_info "Setup complete. To build manually:"
        log_info "  cd ${BUILD_DIR}"
        log_info "  source ${POKY_DIR}/oe-init-build-env ${BUILD_DIR}"
        log_info "  bitbake ${IMAGE}"
        return 0
    fi

    log_step "Building ${IMAGE} (this will take a while)..."
    set +u
    bitbake ${IMAGE} ${BITBAKE_ARGS}
    set -u

    # Build ISO if image succeeded
    log_step "Building bootable ISO..."
    if command -v superlite-boot &>/dev/null; then
        superlite-boot --build-dir "$BUILD_DIR" --output "${SCRIPT_DIR}/superlite-os-$(date +%Y%m%d).iso"
    elif [[ -f "${META_SUPERLITE}/recipes-apps/superlite-live/superlite-live/superlite-boot.sh" ]]; then
        bash "${META_SUPERLITE}/recipes-apps/superlite-live/superlite-live/superlite-boot.sh" \
            --build-dir "$BUILD_DIR" \
            --output "${SCRIPT_DIR}/superlite-os-$(date +%Y%m%d).iso"
    else
        log_warn "superlite-boot not found. Run it manually to create the ISO."
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║     SuperLite OS — Yocto Build System        ║"
    echo "║  Alpine Linux + LabWC Wayland Desktop        ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    if [[ "$CLEAN" == true ]]; then
        log_info "Cleaning build directory..."
        rm -rf "$BUILD_DIR"/{tmp*,sstate-cache,cache}
    fi

    check_deps
    setup_poky
    configure_build
    build_image

    echo ""
    log_info "═══════════════════════════════════════════════"
    log_info "Build complete!"
    log_info "ISO: ${SCRIPT_DIR}/superlite-os-$(date +%Y%m%d).iso"
    log_info ""
    log_info "Write to USB:"
    log_info "  sudo dd if=superlite-os-*.iso of=/dev/sdX bs=4M status=progress"
    log_info "═══════════════════════════════════════════════"
}

main "$@"
