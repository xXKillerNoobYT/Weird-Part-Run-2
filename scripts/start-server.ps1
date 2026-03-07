# Wired-Part Server Startup Script (Windows)
# ============================================
# Run this to start the shop server.
# Usage: Right-click → "Run with PowerShell" or: powershell -File scripts\start-server.ps1

$ErrorActionPreference = "Stop"
$ROOT = Split-Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    Wired-Part Shop Server" -ForegroundColor Cyan
Write-Host "  ══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 1. Check Python
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "  ERROR: Python not found." -ForegroundColor Red
    Write-Host "  Install Python 3.12+ from https://python.org" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
$pyVersion = & python --version 2>&1
Write-Host "  Python: $pyVersion" -ForegroundColor Gray

# 2. Check/create virtual environment
$venvPath = Join-Path $ROOT "backend\.venv"
if (-not (Test-Path $venvPath)) {
    Write-Host "  Creating virtual environment..." -ForegroundColor Yellow
    & python -m venv $venvPath
    & "$venvPath\Scripts\pip.exe" install -r (Join-Path $ROOT "backend\requirements.txt")
    Write-Host "  Dependencies installed." -ForegroundColor Green
}

# 3. Build frontend if needed
$distPath = Join-Path $ROOT "frontend\dist"
if (-not (Test-Path $distPath)) {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        Write-Host "  Building frontend..." -ForegroundColor Yellow
        Set-Location (Join-Path $ROOT "frontend")
        & npm install --silent
        & npm run build
        Write-Host "  Frontend built." -ForegroundColor Green
    } else {
        Write-Host "  WARNING: npm not found. Frontend will not be served." -ForegroundColor Yellow
        Write-Host "  Install Node.js from https://nodejs.org to enable frontend serving." -ForegroundColor Yellow
    }
}

# 4. Detect LAN IP
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notmatch "^169\."
} | Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  Server starting at:" -ForegroundColor Green
Write-Host "    Local:   http://localhost:8000" -ForegroundColor White
if ($lanIp) {
    Write-Host "    Network: http://${lanIp}:8000" -ForegroundColor White
    Write-Host ""
    Write-Host "  Field devices connect to: http://${lanIp}:8000" -ForegroundColor Yellow
}
Write-Host "  API docs: http://localhost:8000/docs" -ForegroundColor Gray
Write-Host ""
Write-Host "  Press Ctrl+C to stop the server." -ForegroundColor Gray
Write-Host ""

# 5. Start the server
Set-Location (Join-Path $ROOT "backend")
& "$venvPath\Scripts\uvicorn.exe" app.main:app --host 0.0.0.0 --port 8000 --workers 2 --log-level info
