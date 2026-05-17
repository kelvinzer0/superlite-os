#!/bin/bash
# ============================================================================
# SuperLite OS — Build Script (Alpine Native)
# ============================================================================
# Replaces Yocto entirely. Uses Alpine's mkimage.sh — simple, fast, reliable.
#
# Usage:
#   ./build.sh                    # Build ISO (requires root or Docker)
#   ./build.sh --setup-only       # Just set up the build environment
#   ./build.sh --docker           # Build inside Docker container
#   ./build.sh --output /path     # Custom output path
#
# Requirements: Alpine Linux (or Docker)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APORTS_DIR="${SCRIPT_DIR}/aports"
OUTPUT=""
SETUP_ONLY=false
USE_DOCKER=false
TAG="superlite"
VARIANT="superlite"  # superlite | superlite-install | superlite-parted

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup-only) SETUP_ONLY=true; shift ;;
        --docker)     USE_DOCKER=true; shift ;;
        --output)     OUTPUT="$2"; shift 2 ;;
        --tag)        TAG="$2"; shift 2 ;;
        --variant)    VARIANT="$2"; shift 2 ;;
        --all)        VARIANT="all"; shift ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --variant NAME   Build variant: superlite (default), superlite-install, superlite-parted"
            echo "  --all            Build all three variants"
            echo "  --setup-only     Just set up the build environment"
            echo "  --docker         Build inside Docker container"
            echo "  --output PATH    Custom output path"
            echo "  --tag NAME       Build tag"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

log() { echo "[build] $*"; }

# ── Build function (reused for all variants) ──────────────────────────────────
build_variant() {
    local variant="$1"
    local tag="$2"
    local output_dir="$3"

    log "Building variant: ${variant} (tag: ${tag})"

    if [[ "$USE_DOCKER" == true ]]; then
        _docker_build "$variant" "$tag" "$output_dir"
    else
        _native_build "$variant" "$tag" "$output_dir"
    fi
}

_docker_build() {
    local variant="$1"
    local tag="$2"
    local output_dir="$3"

    log "Building ${variant} inside Docker..."
    mkdir -p "$output_dir"

    docker run --rm \
        --privileged \
        -v "${SCRIPT_DIR}:/build" \
        -w /build \
        alpine:edge \
        sh -c "
            set -e
            apk add --no-cache alpine-sdk build-base apk-tools alpine-conf \
                busybox fakeroot syslinux xorriso squashfs-tools mtools dosfstools \
                grub-efi grub-bios lua5.4 git

            adduser -D build
            addgroup build abuild 2>/dev/null || true
            echo 'build:build' | chpasswd
            echo 'build ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

            su build -c 'abuild-keygen -a -n'
            git clone --depth=1 git://git.alpinelinux.org/aports /home/build/aports

            cp /build/aports/scripts/mkimg.${variant}.sh /home/build/aports/scripts/
            cp /build/aports/scripts/genapkovl-${variant}.sh /home/build/aports/scripts/
            chmod +x /home/build/aports/scripts/genapkovl-${variant}.sh
            ln -sf /build/dotfiles /home/build/aports/scripts/dotfiles
            ln -sf /build/alpine /home/build/aports/scripts/alpine
            chown -R build:build /home/build/aports

            mkdir -p /build/output/${variant}
            chown build:build /build/output/${variant}

            PUBKEY=\$(ls /home/build/.abuild/build-*.rsa.pub 2>/dev/null | head -1)
            PRIVKEY=\$(ls /home/build/.abuild/build-*.rsa 2>/dev/null | head -1)
            cp \"\$PUBKEY\" /etc/apk/keys/

            su build -c \"
                PACKAGER_PRIVKEY=\$PRIVKEY \\
                PACKAGER_PUBKEY=\$PUBKEY \\
                cd /home/build/aports/scripts && ./mkimage.sh \\
                    --profile ${variant} \\
                    --arch x86_64 \\
                    --hostkeys \\
                    --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \\
                    --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \\
                    --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \\
                    --outdir /build/output/${variant}/ \\
                    --tag '${tag}'
            \"
        "
    log "ISO built at: ${output_dir}/"
}

_native_build() {
    local variant="$1"
    local tag="$2"
    local output_dir="$3"

    if [[ ! -f /etc/alpine-release ]]; then
        log "WARNING: Not running on Alpine. Use --docker for containerized build."
    fi

    log "Installing build dependencies..."
    apk add --no-cache \
        alpine-sdk build-base apk-tools alpine-conf \
        busybox fakeroot syslinux xorriso squashfs-tools mtools dosfstools \
        grub-efi grub-bios lua5.4 git 2>/dev/null || true

    if ! ls ~/.abuild/build-*.rsa >/dev/null 2>&1; then
        log "Generating signing key..."
        abuild-keygen -a -n
    fi

    if [[ ! -d /root/aports ]]; then
        log "Cloning aports..."
        git clone --depth=1 git://git.alpinelinux.org/aports /root/aports
    fi

    log "Installing ${variant} profile..."
    cp "${APORTS_DIR}/scripts/mkimg.${variant}.sh"   /root/aports/scripts/
    cp "${APORTS_DIR}/scripts/genapkovl-${variant}.sh" /root/aports/scripts/
    chmod +x /root/aports/scripts/genapkovl-${variant}.sh

    if [[ -d "${SCRIPT_DIR}/dotfiles" ]]; then
        ln -sf "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles 2>/dev/null || \
            cp -r "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles
    fi

    if [[ "$SETUP_ONLY" == true ]]; then
        log "Setup complete. Build manually with:"
        log "  cd /root/aports/scripts && PACKAGER_PRIVKEY=~/.abuild/build-*.rsa ./mkimage.sh --profile ${variant} --arch x86_64 --hostkeys --outdir ~/iso/ --tag ${tag}"
        return 0
    fi

    log "Building ${variant} ISO..."
    mkdir -p "$output_dir"

    cd /root/aports/scripts
    PUBKEY=$(ls ~/.abuild/build-*.rsa.pub | head -1)
    PRIVKEY=$(ls ~/.abuild/build-*.rsa | head -1)
    cp "$PUBKEY" /etc/apk/keys/
    PACKAGER_PRIVKEY="$PRIVKEY" \
    PACKAGER_PUBKEY="$PUBKEY" \
    ./mkimage.sh \
        --profile "$variant" \
        --arch x86_64 \
        --hostkeys \
        --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
        --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
        --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        --outdir "$output_dir" \
        --tag "$tag"
}

# ── Main ──────────────────────────────────────────────────────────────────────
ISO_OUT="${OUTPUT:-${SCRIPT_DIR}/output}"

if [[ "$VARIANT" == "all" ]]; then
    for v in superlite superlite-install superlite-parted; do
        build_variant "$v" "$TAG" "${ISO_OUT}/${v}"
    done
    log "═══════════════════════════════════════════════"
    log "All ISOs built in: ${ISO_OUT}/"
    log "═══════════════════════════════════════════════"
else
    build_variant "$VARIANT" "$TAG" "${ISO_OUT}/${VARIANT}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
ISO_FILES=$(find "$ISO_OUT" -name "*.iso" -type f 2>/dev/null)
if [[ -n "$ISO_FILES" ]]; then
    log "═══════════════════════════════════════════════"
    while IFS= read -r iso; do
        ISO_SIZE=$(du -sh "$iso" | cut -f1)
        log "  $iso ($ISO_SIZE)"
    done <<< "$ISO_FILES"
    log "Boot: UEFI + Legacy BIOS"
    log "═══════════════════════════════════════════════"
else
    log "ERROR: No ISO found in ${ISO_OUT}/"
    exit 1
fi
