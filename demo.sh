#!/bin/bash
# SuperLite OS — Quick Demo (Xvfb + openbox + SuperLite DE + noVNC + cloudflared)
# Usage: ./demo.sh [--port 6080]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOVNC_PORT="${1:-6080}"
DISPLAY_NUM=":99"

export PYTHONPATH="$SCRIPT_DIR:$PYTHONPATH"
export DISPLAY="$DISPLAY_NUM"

PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT INT TERM

echo "[1/5] Xvfb on $DISPLAY_NUM..."
Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 -ac +extension GLX +render -noreset &
PIDS+=($!); sleep 1

echo "[2/5] Openbox..."
openbox &
PIDS+=($!); sleep 1

echo "[3/5] SuperLite DE..."
cd "$SCRIPT_DIR"
python3 -m core.session &
PIDS+=($!); sleep 2

echo "[4/5] x11vnc + noVNC..."
x11vnc -display "$DISPLAY_NUM" -nopw -listen 0.0.0.0 -rfbport 5900 -forever -shared -bg -o /tmp/x11vnc.log
websockify --web=/usr/share/novnc "$NOVNC_PORT" localhost:5900 &
PIDS+=($!); sleep 1

echo "[5/5] cloudflared..."
cloudflared tunnel --url "http://localhost:$NOVNC_PORT" --no-autoupdate > /tmp/cf-demo.log 2>&1 &
PIDS+=($!); sleep 5

TUNNEL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cf-demo.log | head -1)
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              SuperLite OS — Demo                         ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  noVNC:  http://localhost:$NOVNC_PORT/vnc.html                  ║"
[ -n "$TUNNEL" ] && echo "║  Public: $TUNNEL  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
wait -n "${PIDS[@]}" 2>/dev/null || true
