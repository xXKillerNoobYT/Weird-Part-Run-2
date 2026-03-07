# Wired-Part Database Restore Script (Windows)
# =============================================
# Restores a SQLite database from a backup file.
# Stops the server, swaps the DB, and optionally restarts.
#
# Usage:
#   powershell -File scripts\restore-db.ps1                         # interactive pick
#   powershell -File scripts\restore-db.ps1 -BackupFile backups\wiredpart_2026-03-06_0000.db

param(
    [string]$BackupFile
)

$ROOT = Split-Path $PSScriptRoot -Parent
$DB = Join-Path $ROOT "backend\wiredpart.db"
$BACKUP_DIR = Join-Path $ROOT "backups"

# Check .env for custom DB path
$envFile = Join-Path $ROOT ".env"
if (Test-Path $envFile) {
    $dbLine = Get-Content $envFile | Where-Object { $_ -match "^DATABASE_PATH=" }
    if ($dbLine) {
        $customPath = ($dbLine -split "=", 2)[1].Trim()
        if ($customPath) { $DB = $customPath }
    }
}

# If no backup file specified, list available backups
if (-not $BackupFile) {
    $backups = Get-ChildItem $BACKUP_DIR -Filter "wiredpart_*.db" -ErrorAction SilentlyContinue |
        Sort-Object CreationTime -Descending

    if (-not $backups -or $backups.Count -eq 0) {
        Write-Host "ERROR: No backups found in $BACKUP_DIR" -ForegroundColor Red
        exit 1
    }

    Write-Host "`nAvailable backups:" -ForegroundColor Cyan
    for ($i = 0; $i -lt [math]::Min($backups.Count, 10); $i++) {
        $b = $backups[$i]
        $size = [math]::Round($b.Length / 1MB, 2)
        Write-Host "  [$($i+1)] $($b.Name)  ($size MB)  $($b.CreationTime)"
    }

    $choice = Read-Host "`nEnter number to restore (or 'q' to cancel)"
    if ($choice -eq 'q' -or $choice -eq '') { exit 0 }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $backups.Count) {
        Write-Host "Invalid choice." -ForegroundColor Red
        exit 1
    }
    $BackupFile = $backups[$idx].FullName
}

# Resolve to full path if relative
if (-not [System.IO.Path]::IsPathRooted($BackupFile)) {
    $BackupFile = Join-Path $ROOT $BackupFile
}

if (-not (Test-Path $BackupFile)) {
    Write-Host "ERROR: Backup file not found: $BackupFile" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Wired-Part Database Restore ===" -ForegroundColor Cyan
Write-Host "Source:  $BackupFile" -ForegroundColor White
Write-Host "Target:  $DB" -ForegroundColor White

$confirm = Read-Host "`nThis will REPLACE the current database. Continue? (y/N)"
if ($confirm -ne 'y') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# 1. Create a safety backup of current DB
$safetyBackup = Join-Path $BACKUP_DIR "wiredpart_pre-restore_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').db"
if (Test-Path $DB) {
    Copy-Item $DB $safetyBackup
    Write-Host "Safety backup created: $safetyBackup" -ForegroundColor Gray
}

# 2. Stop the server (if running)
$procs = Get-Process -Name "python*","uvicorn*" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "wiredpart|app.main" }
if ($procs) {
    Write-Host "Stopping server..." -ForegroundColor Yellow
    $procs | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# 3. Restore
Copy-Item $BackupFile $DB -Force
$size = [math]::Round((Get-Item $DB).Length / 1MB, 2)
Write-Host "`nDatabase restored successfully ($size MB)." -ForegroundColor Green
Write-Host "Run 'scripts\start-server.ps1' to restart the server." -ForegroundColor Yellow
