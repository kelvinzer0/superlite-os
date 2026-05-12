#!/bin/bash
# SuperLite OS - Build Script
# Usage: ./build.sh [iso|img|both] [--no-drivers]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE="${HOME}/.superlite/build"
TARGET="${1:-iso}"
INCLUDE_DRIVERS=true

# Parse args
for arg in "$@"; do
    case "$arg" in
        --no-drivers) INCLUDE_DRIVERS=false ;;
        --workspace=*) WORKSPACE="${arg#*=}" ;;
    esac
done

echo "=========================================="
echo "  SuperLite OS Build System"
echo "  Target: ${TARGET}"
echo "  Workspace: ${WORKSPACE}"
echo "=========================================="

# Check dependencies
check_dep() {
    if ! command -v "$1" &>/dev/null; then
        echo "[ERROR] $1 not found. Install with: apt install $2"
        exit 1
    fi
}

check_dep "python3" "python3"
check_dep "debootstrap" "debootstrap"
check_dep "xorriso" "xorriso"
check_dep "sfdisk" "util-linux"

# Step 1: Dump drivers (if needed)
if [ "$INCLUDE_DRIVERS" = true ]; then
    DUMP_DIR="${HOME}/.superlite/driver-dump"
    if [ ! -f "$DUMP_DIR/manifest.json" ]; then
        echo "[1/4] Dumping host drivers..."
        python3 -c "
import sys
sys.path.insert(0, '${PROJECT_DIR}')
from drivers.dump import DriverDump
d = DriverDump('${DUMP_DIR}')
d.dump_all()
"
    else
        echo "[1/4] Using existing driver dump"
    fi
else
    echo "[1/4] Skipping driver dump"
fi

# Step 2: Build rootfs
echo "[2/4] Building rootfs..."
python3 -c "
import sys
sys.path.insert(0, '${PROJECT_DIR}')
from drivers.crosschain import CrossChainBuilder, BuildConfig
config = BuildConfig()
builder = CrossChainBuilder(config, '${WORKSPACE}')
driver_dir = '${DUMP_DIR}' if ${INCLUDE_DRIVERS} else None
builder.build(driver_dump_dir=driver_dir)
"

# Step 3: Generate ISO
if [ "$TARGET" = "iso" ] || [ "$TARGET" = "both" ]; then
    echo "[3/4] Generating ISO..."
    # ISO generation would go here
    echo "  ISO generation requires xorriso + isolinux"
fi

# Step 4: Write to flashdisk (optional)
echo "[4/4] Build complete!"
echo ""
echo "To write to flashdisk:"
echo "  sudo dd if=${WORKSPACE}/superlite-os.img of=/dev/sdX bs=4M status=progress"
echo ""
echo "Or use the cross-chain builder directly:"
echo "  python3 -m superlite.build --target img --size 4096"
