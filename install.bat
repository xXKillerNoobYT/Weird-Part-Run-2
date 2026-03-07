@echo off
:: Wired-Part — Windows Installer
:: ================================
:: Installs backend (Python) and frontend (Node.js) dependencies.
:: Each step fails gracefully — if one part fails, the rest still attempt.
:: Safe to re-run to repair or update.

setlocal EnableDelayedExpansion
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "VENV=%ROOT%\backend\.venv"

:: Track which steps passed / failed
set "STEP_PYTHON=skipped"
set "STEP_VENV=skipped"
set "STEP_BACKEND=skipped"
set "STEP_NODE=skipped"
set "STEP_NPM=skipped"
set "STEP_BUILD=skipped"

echo.
echo   ══════════════════════════════════════════
echo     Wired-Part  ^|  Install
echo   ══════════════════════════════════════════
echo.

:: ════════════════════════════════════════════
:: BACKEND
:: ════════════════════════════════════════════
echo   [Backend]
echo.

:: ── 1. Python check ──────────────────────────────────────────────────────────
where python >nul 2>&1
if errorlevel 1 (
    echo     Python not found — backend install skipped.
    echo     Install Python 3.12+ from https://python.org
    echo     Make sure "Add Python to PATH" is checked during install.
    set "STEP_PYTHON=FAILED"
    set "STEP_VENV=skipped"
    set "STEP_BACKEND=skipped"
    goto :frontend
)

for /f "tokens=2 delims= " %%v in ('python --version 2^>^&1') do set "PY_VER=%%v"
echo     Python: %PY_VER%
set "STEP_PYTHON=ok"

for /f "tokens=1,2 delims=." %%a in ("%PY_VER%") do (
    set "PY_MAJOR=%%a"
    set "PY_MINOR=%%b"
)
if %PY_MAJOR% EQU 3 if %PY_MINOR% LSS 12 (
    echo     WARNING: Python 3.12+ recommended. Found %PY_VER%.
)

:: ── 2. Virtual environment ────────────────────────────────────────────────────
if not exist "%VENV%\Scripts\activate.bat" (
    echo     Creating virtual environment...
    python -m venv "%VENV%" >nul 2>&1
    if errorlevel 1 (
        echo     ERROR: Could not create virtual environment.
        set "STEP_VENV=FAILED"
        set "STEP_BACKEND=skipped"
        goto :frontend
    )
    echo     Virtual environment created.
) else (
    echo     Virtual environment exists.
)
set "STEP_VENV=ok"

:: ── 3. pip install ────────────────────────────────────────────────────────────
echo     Installing Python dependencies...
"%VENV%\Scripts\pip.exe" install --upgrade pip --quiet 2>nul
"%VENV%\Scripts\pip.exe" install -r "%ROOT%\backend\requirements.txt"
if errorlevel 1 (
    echo     ERROR: pip install failed. Check backend\requirements.txt and try again.
    set "STEP_BACKEND=FAILED"
    goto :frontend
)
echo     Backend dependencies installed.
set "STEP_BACKEND=ok"

:: ════════════════════════════════════════════
:: FRONTEND
:: ════════════════════════════════════════════
:frontend
echo.
echo   [Frontend]
echo.

:: ── 4. Node.js check ─────────────────────────────────────────────────────────
where node >nul 2>&1
if errorlevel 1 (
    echo     Node.js not found — frontend install skipped.
    echo     Install Node.js 18+ from https://nodejs.org
    set "STEP_NODE=FAILED"
    set "STEP_NPM=skipped"
    set "STEP_BUILD=skipped"
    goto :summary
)

node --version > "%TEMP%\wiredpart_node.tmp" 2>&1
set /p NODE_VER=<"%TEMP%\wiredpart_node.tmp"
del "%TEMP%\wiredpart_node.tmp" >nul 2>&1
echo     Node.js: %NODE_VER%
set "STEP_NODE=ok"

:: ── 5. npm install ───────────────────────────────────────────────────────────
echo     Installing frontend dependencies...
cd /d "%ROOT%\frontend"
call npm install
if errorlevel 1 (
    echo     ERROR: npm install failed.
    set "STEP_NPM=FAILED"
    set "STEP_BUILD=skipped"
    goto :summary
)
echo     Frontend dependencies installed.
set "STEP_NPM=ok"

:: ── 6. Frontend build ─────────────────────────────────────────────────────────
echo     Building frontend...
call npm run build
if errorlevel 1 (
    echo     ERROR: Frontend build failed. Run launch.bat — the dev server will still work.
    set "STEP_BUILD=FAILED"
    goto :summary
)
echo     Frontend built successfully.
set "STEP_BUILD=ok"

:: ════════════════════════════════════════════
:: SUMMARY
:: ════════════════════════════════════════════
:summary
cd /d "%ROOT%"
echo.
echo   ══════════════════════════════════════════
echo     Install Summary
echo   ══════════════════════════════════════════
echo.
echo     Python found    : %STEP_PYTHON%
echo     Virtual env     : %STEP_VENV%
echo     Backend deps    : %STEP_BACKEND%
echo     Node.js found   : %STEP_NODE%
echo     Frontend deps   : %STEP_NPM%
echo     Frontend build  : %STEP_BUILD%
echo.

:: Determine overall outcome
set "CAN_LAUNCH=no"
if "%STEP_BACKEND%"=="ok" set "CAN_LAUNCH=backend"
if "%STEP_NPM%"=="ok" set "CAN_LAUNCH=both"

if "%CAN_LAUNCH%"=="both" (
    echo     Ready! Run launch.bat to start the application.
) else if "%CAN_LAUNCH%"=="backend" (
    echo     Backend ready. Frontend skipped.
    echo     Run launch.bat — the pre-built bundle will be served if available.
    echo     Fix frontend issues above and re-run to enable the dev server.
) else (
    echo     Nothing installed successfully.
    echo     Fix the errors above and re-run install.bat.
)

if "%STEP_PYTHON%"=="FAILED" (
    echo.
    echo     To fix backend: install Python 3.12+ from https://python.org
)
if "%STEP_NODE%"=="FAILED" (
    echo.
    echo     To fix frontend: install Node.js 18+ from https://nodejs.org
)

echo.
echo   ══════════════════════════════════════════
echo.
pause
endlocal
