@echo off
:: Wired-Part — Windows Launcher
:: ================================
:: Double-click to start BOTH the backend API server and the frontend dev server.
:: Run install.bat first if you haven't already.
::
:: What starts:
::   Backend  — http://localhost:8000   (FastAPI + API docs at /docs)
::   Frontend — http://localhost:5173   (Vite dev server with hot-reload)
::   Network  — http://<LAN-IP>:8000    (for field devices on the same network)

setlocal EnableDelayedExpansion
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "VENV=%ROOT%\backend\.venv"

echo.
echo   ══════════════════════════════════════════
echo     Wired-Part  ^|  Starting...
echo   ══════════════════════════════════════════
echo.

:: ── Check virtual environment ─────────────────────────────────────────────────
if not exist "%VENV%\Scripts\uvicorn.exe" (
    echo   ERROR: Backend not installed.
    echo   Please run install.bat first.
    echo.
    pause
    exit /b 1
)

:: ── Detect LAN IP ─────────────────────────────────────────────────────────────
set "LAN_IP="
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4" ^| findstr /v "169.254"') do (
    set "IP_LINE=%%a"
    set "IP_LINE=!IP_LINE: =!"
    if not defined LAN_IP set "LAN_IP=!IP_LINE!"
)

echo.
echo   Starting services:
echo     Backend  : http://localhost:8000
echo     Frontend : http://localhost:5173
if defined LAN_IP (
    echo     Network  : http://!LAN_IP!:8000
    echo.
    echo   Field devices connect to: http://!LAN_IP!:8000
)
echo.
echo   Each service opens in its own window.
echo   Close both windows to stop the application.
echo.

:: ── Launch backend in a new window ───────────────────────────────────────────
start "Wired-Part — Backend (port 8000)" cmd /k ^
    "cd /d "%ROOT%\backend" && echo. && echo   [Backend] Starting... && echo. && "%VENV%\Scripts\uvicorn.exe" app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info"

:: ── Launch frontend in a new window ──────────────────────────────────────────
where node >nul 2>&1
if not errorlevel 1 (
    if exist "%ROOT%\frontend\node_modules" (
        start "Wired-Part — Frontend (port 5173)" cmd /k ^
            "cd /d "%ROOT%\frontend" && echo. && echo   [Frontend] Starting Vite dev server... && echo. && npm run dev"
    ) else (
        echo   WARNING: Frontend not installed. Run install.bat to enable the dev server.
    )
) else (
    echo   Node.js not found — frontend dev server skipped.
    echo   The backend will serve the pre-built frontend if available.
)

echo.
echo   Both servers launched in separate windows.
echo   You can close this window.
echo.
timeout /t 5 >nul
endlocal
