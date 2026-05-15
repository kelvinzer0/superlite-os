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
        sh -c '
            set -e

            # Install dependencies
            apk add --no-cache alpine-sdk build-base apk-tools alpine-conf \
                busybox fakeroot syslinux xorriso squashfs-tools mtools dosfstools \
                grub-efi grub-bios lua5.4 git

            # Create build user
            adduser -D build
            addgroup build abuild 2>/dev/null || true
            echo "build:build" | chpasswd
            echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

            # Generate signing key
            su build -c "abuild-keygen -a -n"

            # Clone aports
            git clone --depth=1 git://git.alpinelinux.org/aports /home/build/aports

            # Copy SuperLite profile + overlay
            cp /build/aports/scripts/mkimg.superlite.sh /home/build/aports/scripts/
            cp /build/aports/scripts/genapkovl-superlite.sh /home/build/aports/scripts/
            chmod +x /home/build/aports/scripts/genapkovl-superlite.sh
            ln -sf /build/dotfiles /home/build/aports/scripts/dotfiles
            chown -R build:build /home/build/aports

            # Prepare output dir
            mkdir -p /build/output
            chown build:build /build/output

            # Build ISO (must run as non-root)
            su build -c "
                PACKAGER_PRIVKEY=\$(ls /home/build/.abuild/build-*.rsa | head -1) \
                PACKAGER_PUBKEY=\$(ls /home/build/.abuild/build-*.rsa.pub | head -1) \
                cd /home/build/aports/scripts && ./mkimage.sh \
                    --profile superlite \
                    --arch x86_64 \
                    --hostkeys \
                    --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
                    --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
                    --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
                    --outdir /build/output/ \
                    --tag '"${TAG}"'
            "

            # Inject signing key into apkovl overlay for CDROM trust
            PUBKEY=$(ls /home/build/.abuild/build-*.rsa.pub 2>/dev/null | head -1)
            OVERLAY=$(find /build/output -name "*.apkovl.tar.gz" 2>/dev/null | head -1)
            if [ -n "$PUBKEY" ] && [ -n "$OVERLAY" ]; then
                echo "Injecting signing key into overlay..."
                TMPD=$(mktemp -d)
                cd "$TMPD"
                tar xzf "$OVERLAY"
                mkdir -p etc/apk/keys
                cp "$PUBKEY" etc/apk/keys/
                tar czf "$OVERLAY" etc/
                cd /
                rm -rf "$TMPD"
                echo "Key injected into $OVERLAY"
            fi
        '
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

# ── Generate signing key if needed ────────────────────────────────────────────
if ! ls ~/.abuild/build-*.rsa >/dev/null 2>&1; then
    log "Generating signing key..."
    abuild-keygen -a -n
fi

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

if [[ -d "${SCRIPT_DIR}/dotfiles" ]]; then
    ln -sf "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles 2>/dev/null || \
        cp -r "${SCRIPT_DIR}/dotfiles" /root/aports/scripts/dotfiles
fi

if [[ "$SETUP_ONLY" == true ]]; then
    log "Setup complete. Build manually with:"
    log "  cd /root/aports/scripts && PACKAGER_PRIVKEY=~/.abuild/build-*.rsa ./mkimage.sh --profile superlite --arch x86_64 --hostkeys --outdir ~/iso/ --tag ${TAG}"
    exit 0
fi

# ── Build ISO ─────────────────────────────────────────────────────────────────
log "Building SuperLite OS ISO..."
ISO_OUT="${OUTPUT:-${SCRIPT_DIR}/output}"
mkdir -p "$ISO_OUT"

cd /root/aports/scripts
PACKAGER_PRIVKEY=$(ls ~/.abuild/build-*.rsa | head -1) \
PACKAGER_PUBKEY=$(ls ~/.abuild/build-*.rsa.pub | head -1) \
./mkimage.sh \
    --profile superlite \
    --arch x86_64 \
    --hostkeys \
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
    --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    --outdir "$ISO_OUT" \
    --tag "$TAG"

# Inject key into overlay
PUBKEY=$(ls ~/.abuild/build-*.rsa.pub 2>/dev/null | head -1)
OVERLAY=$(find "$ISO_OUT" -name "*.apkovl.tar.gz" 2>/dev/null | head -1)
if [ -n "$PUBKEY" ] && [ -n "$OVERLAY" ]; then
    log "Injecting signing key into overlay..."
    TMPD=$(mktemp -d)
    cd "$TMPD"
    tar xzf "$OVERLAY"
    mkdir -p etc/apk/keys
    cp "$PUBKEY" etc/apk/keys/
    tar czf "$OVERLAY" etc/
    cd /
    rm -rf "$TMPD"
fi

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
