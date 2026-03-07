#!/bin/bash
# Wired-Part Server Startup Script (Mac/Linux)
# =============================================
# Usage: chmod +x scripts/start-server.sh && ./scripts/start-server.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "  ══════════════════════════════════════════"
echo "    Wired-Part Shop Server"
echo "  ══════════════════════════════════════════"
echo ""

# 1. Check Python
if ! command -v python3 &> /dev/null; then
    echo "  ERROR: Python 3 not found."
    echo "  Install Python 3.12+ from https://python.org"
    exit 1
fi
echo "  Python: $(python3 --version)"

# 2. Check/create virtual environment
VENV="$ROOT/backend/.venv"
if [ ! -d "$VENV" ]; then
    echo "  Creating virtual environment..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -r "$ROOT/backend/requirements.txt"
    echo "  Dependencies installed."
fi

# 3. Build frontend if needed
if [ ! -d "$ROOT/frontend/dist" ]; then
    if command -v npm &> /dev/null; then
        echo "  Building frontend..."
        cd "$ROOT/frontend"
        npm install --silent
        npm run build
        echo "  Frontend built."
    else
        echo "  WARNING: npm not found. Frontend will not be served."
        echo "  Install Node.js from https://nodejs.org to enable frontend serving."
    fi
fi

# 4. Detect LAN IP
if command -v ifconfig &> /dev/null; then
    LAN_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
elif command -v hostname &> /dev/null; then
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

echo ""
echo "  Server starting at:"
echo "    Local:   http://localhost:8000"
if [ -n "$LAN_IP" ]; then
    echo "    Network: http://${LAN_IP}:8000"
    echo ""
    echo "  Field devices connect to: http://${LAN_IP}:8000"
fi
echo "  API docs: http://localhost:8000/docs"
echo ""
echo "  Press Ctrl+C to stop the server."
echo ""

# 5. Start the server
cd "$ROOT/backend"
"$VENV/bin/uvicorn" app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info
