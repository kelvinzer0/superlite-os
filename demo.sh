#!/bin/bash
# SuperLite OS - Full Demo Environment
# Sets up: Xvfb → openbox (host WM) → SuperLite DE → x11vnc → noVNC → cloudflared
#
# Usage: ./demo.sh [--port 6080] [--no-tunnel] [--resolution 1920x1080x24]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOVNC_PORT="${NOVNC_PORT:-6080}"
DISPLAY_NUM=":99"
RESOLUTION="1920x1080x24"
NO_TUNNEL=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --port) NOVNC_PORT="$2"; shift 2 ;;
        --resolution) RESOLUTION="$2"; shift 2 ;;
        --no-tunnel) NO_TUNNEL=true; shift ;;
        *) shift ;;
    esac
done

PIDS=()

cleanup() {
    echo ""
    echo "[Demo] Shutting down..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    echo "[Demo] Done."
}
trap cleanup EXIT INT TERM

# ─── 1. Xvfb (virtual framebuffer) ─────────────────────
echo "[1/6] Starting Xvfb on $DISPLAY_NUM ($RESOLUTION)..."
Xvfb "$DISPLAY_NUM" -screen 0 "$RESOLUTION" -ac +extension GLX +render -noreset &
PIDS+=($!)
sleep 1
export DISPLAY="$DISPLAY_NUM"

# ─── 2. Openbox (host window manager) ───────────────────
echo "[2/6] Starting openbox as host WM..."
openbox &
PIDS+=($!)
sleep 1

# ─── 3. SuperLite DE (runs as a GTK window inside openbox)
echo "[3/6] Starting SuperLite DE..."
cd "$SCRIPT_DIR"
export PYTHONPATH="$SCRIPT_DIR:$PYTHONPATH"
python3 -m core.session &
PIDS+=($!)
sleep 2

# ─── 4. x11vnc (X11 → VNC bridge) ─────────────────────
echo "[4/6] Starting x11vnc..."
x11vnc -display "$DISPLAY_NUM" -nopw -listen 0.0.0.0 -rfbport 5900 -forever -shared -bg -o /tmp/x11vnc.log 2>&1
sleep 1

# ─── 5. noVNC + websockify ──────────────────────────────
echo "[5/6] Starting websockify+noVNC on port $NOVNC_PORT..."
NOVNC_DIR="/usr/share/novnc"
websockify --web="$NOVNC_DIR" "$NOVNC_PORT" "localhost:5900" &
PIDS+=($!)
sleep 1

# ─── 6. Cloudflared tunnel (optional) ───────────────────
if [ "$NO_TUNNEL" = false ] && command -v cloudflared &>/dev/null; then
    echo "[6/6] Starting cloudflared tunnel..."
    cloudflared tunnel --url "http://localhost:$NOVNC_PORT" --no-autoupdate > /tmp/cloudflared.log 2>&1 &
    PIDS+=($!)
    sleep 4
    TUNNEL_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
else
    echo "[6/6] Skipping cloudflared tunnel."
    TUNNEL_URL=""
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║            SuperLite OS Demo Environment                 ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  noVNC (local): http://localhost:${NOVNC_PORT}/vnc.html      ║"
if [ -n "$TUNNEL_URL" ]; then
echo "║  Tunnel:        ${TUNNEL_URL}  ║"
fi
echo "║                                                          ║"
echo "║  Xvfb:     $DISPLAY_NUM ($RESOLUTION)                    ║"
echo "║  Host WM:  openbox                                       ║"
echo "║  SuperLite DE running as a GTK4 window                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "[Demo] Press Ctrl+C to stop all services."
echo ""

# Wait
wait -n "${PIDS[@]}" 2>/dev/null || true
