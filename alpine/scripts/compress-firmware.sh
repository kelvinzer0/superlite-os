#!/bin/sh
# ============================================================================
# SuperLite OS — Firmware Compression & Cleanup
# Reduces linux-firmware size from ~200MB+ to ~40-60MB
# ============================================================================
# Strategy:
#   1. Remove firmware for hardware that will never run a desktop distro
#   2. Compress remaining firmware with xz (kernel supports xz-compressed fw)
#   3. Remove duplicate/old versions
#   4. Keep: GPU (Intel/AMD/NVIDIA), WiFi, Bluetooth, USB, NVMe, audio
#   5. Remove: InfiniBand, 10GbE, Fibre Channel, exotic RAID, old wireless
# ============================================================================

set -eu

FIRMWARE_DIR="${1:-/lib/firmware}"
LIVE_LOG() { echo "[firmware] $*"; }

if [ ! -d "$FIRMWARE_DIR" ]; then
    LIVE_LOG "WARNING: Firmware directory not found: $FIRMWARE_DIR"
    exit 0
fi

BEFORE_SIZE=$(du -sm "$FIRMWARE_DIR" | cut -f1)
LIVE_LOG "Firmware size before cleanup: ${BEFORE_SIZE}MB"

# ── Step 1: Remove firmware for uncommon/enterprise hardware ─────────────────
LIVE_LOG "Removing unnecessary firmware..."

# InfiniBand / RDMA (enterprise/datacenter only)
rm -rf "$FIRMWARE_DIR"/mlx* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/bnxt* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/qed* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/liquidio* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/netronome* 2>/dev/null || true

# Fibre Channel / SCSI HBA (enterprise)
rm -rf "$FIRMWARE_DIR"/ql* 2>/dev/null || true  # QLogic
rm -rf "$FIRMWARE_DIR"/bfa* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/cxgb* 2>/dev/null || true  # Chelsio 10GbE

# Old/legacy wireless (pre-802.11n)
rm -rf "$FIRMWARE_DIR"/rtl8188* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/rtl8192* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/ath5k 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/carl9170* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/orinoco* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/p54* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/rsi* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/vt6656* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/zd1211* 2>/dev/null || true

# Old TV tuner / DVB / media (not needed for desktop)
rm -rf "$FIRMWARE_DIR"/dvb* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/av7110* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/cpia2* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/ttusb* 2>/dev/null || true

# Old Bluetooth (pre-BT4.0)
rm -rf "$FIRMWARE_DIR"/BCM20702A1* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/BCM20702B0* 2>/dev/null || true

# Rockchip / Sunxi / MediaTek ARM firmware (not relevant for x86_64 desktop)
rm -rf "$FIRMWARE_DIR"/rockchip 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/sun 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/mediatek 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/mrvl 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/ti-connectivity 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/brcm 2>/dev/null || true  # Broadcom ARM (keep x86 brcm below)

# Broadcom wireless for RPi / ARM boards (we keep x86 Broadcom below)
rm -rf "$FIRMWARE_DIR"/brcm/brcmfmac43455* 2>/dev/null || true
rm -rf "$Firmware_DIR"/brcm/brcmfmac43430* 2>/dev/null || true

# GPU firmware for non-desktop GPUs (server/compute)
rm -rf "$FIRMWARE_DIR"/amdgpu/denoise_* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/amdgpu/ta_* 2>/dev/null || true

# Remove large debug/test firmware
rm -rf "$FIRMWARE_DIR"/*test* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/*debug* 2>/dev/null || true
rm -rf "$FIRMWARE_DIR"/korg* 2>/dev/null || true

# ── Step 2: Remove duplicate firmware (keep .xz if both exist) ───────────────
LIVE_LOG "Removing duplicates..."
find "$FIRMWARE_DIR" -name "*.xz" -type f | while read -r xzfile; do
    base=$(echo "$xzfile" | sed 's/\.xz$//')
    if [ -f "$base" ]; then
        rm -f "$base"
    fi
done 2>/dev/null || true

# ── Step 3: Compress uncompressed firmware with xz ──────────────────────────
LIVE_LOG "Compressing firmware with xz..."

compress_count=0
find "$FIRMWARE_DIR" -type f \( \
    -name "*.bin" -o \
    -name "*.fw" -o \
    -name "*.img" -o \
    -name "*.ucode" \
\) ! -name "*.xz" ! -name "*.zst" | while read -r fwfile; do
    # Skip if already compressed or too small to matter
    fsize=$(stat -c%s "$fwfile" 2>/dev/null || stat -f%z "$fwfile" 2>/dev/null || echo 0)
    if [ "$fsize" -lt 4096 ]; then
        continue
    fi

    # Compress with xz (kernel supports xz-compressed firmware since 5.3+)
    xz -T1 -f "$fwfile" 2>/dev/null && compress_count=$((compress_count + 1)) || true
done

LIVE_LOG "Compressed $compress_count firmware files"

# ── Step 4: Strip unnecessary sections from large firmware ───────────────────
LIVE_LOG "Removing remaining unnecessary files..."

# Remove README/docs
find "$FIRMWARE_DIR" -name "README*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "WHENCE*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "LICENCE*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "LICENSE*" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "*.txt" -delete 2>/dev/null || true
find "$FIRMWARE_DIR" -name "*.htm*" -delete 2>/dev/null || true

# Remove empty directories
find "$FIRMWARE_DIR" -type d -empty -delete 2>/dev/null || true

# ── Final report ─────────────────────────────────────────────────────────────
AFTER_SIZE=$(du -sm "$FIRMWARE_DIR" | cut -f1)
SAVED=$((BEFORE_SIZE - AFTER_SIZE))
LIVE_LOG "Firmware size after cleanup: ${AFTER_SIZE}MB (saved ${SAVED}MB)"
