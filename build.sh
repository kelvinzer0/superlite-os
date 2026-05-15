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

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup-only) SETUP_ONLY=true; shift ;;
        --docker)     USE_DOCKER=true; shift ;;
        --output)     OUTPUT="$2"; shift 2 ;;
        --tag)        TAG="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--setup-only] [--docker] [--output PATH] [--tag NAME]"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

log() { echo "[build] $*"; }

# ── Docker build ──────────────────────────────────────────────────────────────
if [[ "$USE_DOCKER" == true ]]; then
    log "Building inside Docker..."
    docker run --rm \
        --privileged \
        -v "${SCRIPT_DIR}:/build" \
        -w /build \
        alpine:edge \
        sh -c "
            apk add --no-cache alpine-sdk build-base apk-tools alpine-conf \
                busybox fakeroot syslinux xorriso squashfs-tools mtools dosfstools \
                grub-efi grub-bios lua5.4 git &&
            adduser -D build -G abuild &&
            echo 'build:build' | chpasswd &&
            echo 'build ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers &&
            git clone --depth=1 git://git.alpinelinux.org/aports /home/build/aports &&
            chown -R build:build /home/build/aports &&
            cp /build/aports/scripts/mkimg.superlite.sh /home/build/aports/scripts/ &&
            cp /build/aports/scripts/genapkovl-superlite.sh /home/build/aports/scripts/ &&
            ln -sf /build/dotfiles /home/build/aports/scripts/dotfiles &&
            chown -R build:build /home/build/aports/scripts/ &&
            mkdir -p /build/output && chown build:build /build/output &&
            su build -c 'cd /home/build/aports/scripts && ./mkimage.sh \
                --profile superlite \
                --arch x86_64 \
                --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
                --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
                --outdir /build/output/ \
                --tag ${TAG}'
        "
    log "ISO built at: ${SCRIPT_DIR}/output/"
    exit 0
fi

# ── Native build (must be on Alpine) ──────────────────────────────────────────
if [[ ! -f /etc/alpine-release ]]; then
    log "WARNING: Not running on Alpine. Use --docker for containerized build."
    log "Or install Alpine build dependencies first."
fi

# ── Install dependencies ─────────────────────────────────────────────────────
log "Installing build dependencies..."
apk add --no-cache \
    alpine-sdk build-base apk-tools alpine-conf \
    busybox fakeroot syslinux xorriso squashfs-tools mtools dosfstools \
    grub-efi grub-bios lua5.4 git 2>/dev/null || true

# ── Clone aports if needed ────────────────────────────────────────────────────
if [[ ! -d /root/aports ]]; then
    log "Cloning aports..."
    git clone --depth=1 git://git.alpinelinux.org/aports /root/aports
fi

# ── Copy profile scripts ─────────────────────────────────────────────────────
log "Installing SuperLite profile..."
cp "${APORTS_DIR}/scripts/mkimg.superlite.sh"   /root/aports/scripts/
cp "${APORTS_DIR}/scripts/genapkovl-superlite.sh" /root/aports/scripts/
chmod +x /root/aports/scripts/genapkovl-superlite.sh

# ── Copy assets that genapkovl needs ──────────────────────────────────────────
# genapkovl-superlite.sh references $SCRIPT_DIR/../../dotfiles
# We need them accessible relative to the script in aports/scripts
if [[ -d "${SCRIPT_DIR}/dotfiles" ]]; then
    # Create a symlink so the script can find dotfiles
    ln -sf "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles 2>/dev/null || \
        cp -r "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles
fi

if [[ "$SETUP_ONLY" == true ]]; then
    log "Setup complete. Build manually with:"
    log "  cd /root/aports/scripts && ./mkimage.sh --profile superlite --arch x86_64 --outdir /root/iso/ --tag ${TAG}"
    exit 0
fi

# ── Build ISO ─────────────────────────────────────────────────────────────────
log "Building SuperLite OS ISO..."
ISO_OUT="${OUTPUT:-${SCRIPT_DIR}/output}"
mkdir -p "$ISO_OUT"

cd /root/aports/scripts
./mkimage.sh \
    --profile superlite \
    --arch x86_64 \
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
    --outdir "$ISO_OUT" \
    --tag "$TAG"

# ── Done ──────────────────────────────────────────────────────────────────────
ISO_FILE=$(find "$ISO_OUT" -name "*.iso" -type f | head -1)
if [[ -n "$ISO_FILE" ]]; then
    ISO_SIZE=$(du -sh "$ISO_FILE" | cut -f1)
    log "═══════════════════════════════════════════════"
    log "ISO created: $ISO_FILE"
    log "Size: ${ISO_SIZE}"
    log "Boot: UEFI + Legacy BIOS"
    log "Rufus: Compatible (ISO + DD mode)"
    log "Ventoy: Compatible"
    log "═══════════════════════════════════════════════"
else
    log "ERROR: ISO not found in ${ISO_OUT}/"
    exit 1
fi
