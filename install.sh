#!/usr/bin/env bash
# Wired-Part — Mac / Linux Installer
# =====================================
# Installs backend (Python) and frontend (Node.js) dependencies.
# Each step fails gracefully — if one part fails, the rest still attempt.
# Safe to re-run to repair or update.
#
# Usage:
#   chmod +x install.sh && ./install.sh

# Do NOT use set -e — we handle errors manually for graceful fallback
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/backend/.venv"

# Track which steps passed / failed
STEP_PYTHON="skipped"
STEP_VENV="skipped"
STEP_BACKEND="skipped"
STEP_NODE="skipped"
STEP_NPM="skipped"
STEP_BUILD="skipped"

echo ""
echo "  ══════════════════════════════════════════"
echo "    Wired-Part  |  Install"
echo "  ══════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════
# BACKEND
# ════════════════════════════════════════════
echo "  [Backend]"
echo ""

# ── 1. Python check ─────────────────────────────────────────────────────────
PYTHON=""
if command -v python3 &>/dev/null; then
    PYTHON="python3"
elif command -v python &>/dev/null; then
    PYTHON="python"
fi

if [ -z "$PYTHON" ]; then
    echo "    Python not found — backend install skipped."
    echo "    Install Python 3.12+ from https://python.org"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "    Or via Homebrew:  brew install python"
    else
        echo "    Or via apt:  sudo apt install python3 python3-venv python3-pip"
    fi
    STEP_PYTHON="FAILED"
else
    PY_VER=$($PYTHON --version 2>&1 | awk '{print $2}')
    echo "    Python: $PY_VER"
    STEP_PYTHON="ok"

    PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
    if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 12 ]; }; then
        echo "    WARNING: Python 3.12+ recommended. Found $PY_VER."
    fi

    # ── 2. Virtual environment ────────────────────────────────────────────────
    if [ ! -f "$VENV/bin/activate" ]; then
        echo "    Creating virtual environment..."
        if $PYTHON -m venv "$VENV" 2>/dev/null; then
            echo "    Virtual environment created."
            STEP_VENV="ok"
        else
            echo "    ERROR: Could not create virtual environment."
            echo "    On Linux you may need:  sudo apt install python3-venv"
            STEP_VENV="FAILED"
        fi
    else
        echo "    Virtual environment exists."
        STEP_VENV="ok"
    fi

    # ── 3. pip install ────────────────────────────────────────────────────────
    if [ "$STEP_VENV" = "ok" ]; then
        echo "    Installing Python dependencies..."
        "$VENV/bin/pip" install --upgrade pip --quiet 2>/dev/null
        if "$VENV/bin/pip" install -r "$ROOT/backend/requirements.txt"; then
            echo "    Backend dependencies installed."
            STEP_BACKEND="ok"
        else
            echo "    ERROR: pip install failed. Check backend/requirements.txt."
            STEP_BACKEND="FAILED"
        fi
    fi
fi

# ════════════════════════════════════════════
# FRONTEND
# ════════════════════════════════════════════
echo ""
echo "  [Frontend]"
echo ""

# ── 4. Node.js check ────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
    echo "    Node.js not found — frontend install skipped."
    echo "    Install Node.js 18+ from https://nodejs.org"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "    Or via Homebrew:  brew install node"
    else
        echo "    Or via nvm:  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash"
    fi
    STEP_NODE="FAILED"
else
    NODE_VER=$(node --version)
    echo "    Node.js: $NODE_VER"
    STEP_NODE="ok"

    # ── 5. npm install ────────────────────────────────────────────────────────
    echo "    Installing frontend dependencies..."
    cd "$ROOT/frontend"
    if npm install; then
        echo "    Frontend dependencies installed."
        STEP_NPM="ok"
    else
        echo "    ERROR: npm install failed."
        STEP_NPM="FAILED"
    fi

    # ── 6. Frontend build ─────────────────────────────────────────────────────
    if [ "$STEP_NPM" = "ok" ]; then
        echo "    Building frontend..."
        if npm run build; then
            echo "    Frontend built successfully."
            STEP_BUILD="ok"
        else
            echo "    ERROR: Frontend build failed. Run ./launch.sh — the dev server will still work."
            STEP_BUILD="FAILED"
        fi
    fi

    cd "$ROOT"
fi

# ════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════
echo ""
echo "  ══════════════════════════════════════════"
echo "    Install Summary"
echo "  ══════════════════════════════════════════"
echo ""
echo "    Python found    : $STEP_PYTHON"
echo "    Virtual env     : $STEP_VENV"
echo "    Backend deps    : $STEP_BACKEND"
echo "    Node.js found   : $STEP_NODE"
echo "    Frontend deps   : $STEP_NPM"
echo "    Frontend build  : $STEP_BUILD"
echo ""

CAN_LAUNCH="none"
[ "$STEP_BACKEND" = "ok" ] && CAN_LAUNCH="backend"
[ "$STEP_NPM" = "ok" ] && CAN_LAUNCH="both"

if [ "$CAN_LAUNCH" = "both" ]; then
    echo "    Ready! Run ./launch.sh to start the application."
elif [ "$CAN_LAUNCH" = "backend" ]; then
    echo "    Backend ready. Frontend skipped."
    echo "    Run ./launch.sh — the pre-built bundle will be served if available."
    echo "    Fix frontend issues above and re-run to enable the dev server."
else
    echo "    Nothing installed successfully."
    echo "    Fix the errors above and re-run ./install.sh"
fi

[ "$STEP_PYTHON" = "FAILED" ] && echo "" && echo "    To fix backend:  install Python 3.12+ from https://python.org"
[ "$STEP_NODE" = "FAILED" ] && echo "" && echo "    To fix frontend: install Node.js 18+ from https://nodejs.org"

echo ""
echo "  ══════════════════════════════════════════"
echo ""
