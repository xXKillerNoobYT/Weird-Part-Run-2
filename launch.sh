#!/usr/bin/env bash
# Wired-Part — Mac / Linux Launcher
# =====================================
# Starts BOTH the backend API server and the frontend dev server in one command.
# Run ./install.sh first if you haven't already.
#
# What starts:
#   Backend  — http://localhost:8000   (FastAPI + API docs at /docs)
#   Frontend — http://localhost:5173   (Vite dev server with hot-reload)
#   Network  — http://<LAN-IP>:8000    (for field devices on the same network)
#
# Usage:
#   chmod +x launch.sh && ./launch.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/backend/.venv"

echo ""
echo "  ══════════════════════════════════════════"
echo "    Wired-Part  |  Starting..."
echo "  ══════════════════════════════════════════"
echo ""

# ── Check virtual environment ────────────────────────────────────────────────
if [ ! -f "$VENV/bin/uvicorn" ]; then
    echo "  ERROR: Backend not installed."
    echo "  Please run ./install.sh first."
    echo ""
    exit 1
fi

# ── Detect LAN IP ────────────────────────────────────────────────────────────
LAN_IP=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)
else
    if command -v ip &>/dev/null; then
        LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1 || true)
    elif command -v hostname &>/dev/null; then
        LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
fi

echo "  Starting services:"
echo "    Backend  : http://localhost:8000"
echo "    Frontend : http://localhost:5173"
if [ -n "$LAN_IP" ]; then
    echo "    Network  : http://${LAN_IP}:8000"
    echo ""
    echo "  Field devices connect to: http://${LAN_IP}:8000"
fi
echo ""
echo "  Press Ctrl+C to stop both servers."
echo ""

# ── Cleanup on exit ──────────────────────────────────────────────────────────
FRONTEND_PID=""
cleanup() {
    echo ""
    echo "  Stopping servers..."
    if [ -n "$FRONTEND_PID" ] && kill -0 "$FRONTEND_PID" 2>/dev/null; then
        kill "$FRONTEND_PID" 2>/dev/null || true
        wait "$FRONTEND_PID" 2>/dev/null || true
    fi
    echo "  Stopped."
}
trap cleanup EXIT INT TERM

# ── Start frontend dev server (background) ───────────────────────────────────
if command -v node &>/dev/null && [ -d "$ROOT/frontend/node_modules" ]; then
    echo "  [Frontend] Starting Vite dev server..."
    cd "$ROOT/frontend"
    npm run dev &
    FRONTEND_PID=$!
    cd "$ROOT"
    echo "  [Frontend] PID $FRONTEND_PID"
else
    echo "  [Frontend] Skipped — Node.js not found or npm install not run."
    if [ -f "$ROOT/frontend/dist/index.html" ]; then
        echo "  [Frontend] Pre-built bundle will be served by the backend."
    fi
fi

echo ""

# ── Start backend (foreground — holds the terminal) ──────────────────────────
echo "  [Backend] Starting FastAPI server..."
cd "$ROOT/backend"
exec "$VENV/bin/uvicorn" app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info
