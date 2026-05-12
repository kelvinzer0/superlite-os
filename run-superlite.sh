#!/bin/bash
# SuperLite OS - Desktop Session Launcher
# Usage: ./run-superlite.sh [--display :99]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PYTHONPATH="$SCRIPT_DIR:$PYTHONPATH"

# Default to :99 if not set
DISPLAY="${1:-${DISPLAY:-:99}}"
export DISPLAY

echo "[SuperLite] Starting on DISPLAY=$DISPLAY"
echo "[SuperLite] PYTHONPATH=$PYTHONPATH"

exec python3 -m core.session
