# Wired-Part Database Backup Script (Windows)
# =============================================
# Creates a timestamped copy of the SQLite database.
# Keeps the last 30 backups, deletes older ones.
#
# Usage: powershell -File scripts\backup-db.ps1
# Schedule: Windows Task Scheduler → daily at midnight

$ROOT = Split-Path $PSScriptRoot -Parent
$DB = Join-Path $ROOT "backend\wiredpart.db"
$BACKUP_DIR = Join-Path $ROOT "backups"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HHmm"

# Check if using custom DB path from .env
$envFile = Join-Path $ROOT ".env"
if (Test-Path $envFile) {
    $dbLine = Get-Content $envFile | Where-Object { $_ -match "^DATABASE_PATH=" }
    if ($dbLine) {
        $customPath = ($dbLine -split "=", 2)[1].Trim()
        if (Test-Path $customPath) {
            $DB = $customPath
        }
    }
}

if (-not (Test-Path $DB)) {
    Write-Host "ERROR: Database not found at $DB" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

$backupFile = Join-Path $BACKUP_DIR "wiredpart_$TIMESTAMP.db"
Copy-Item $DB $backupFile
$size = [math]::Round((Get-Item $backupFile).Length / 1MB, 2)
Write-Host "Backup saved: wiredpart_$TIMESTAMP.db ($size MB)" -ForegroundColor Green

# Keep only last 30 backups
$old = Get-ChildItem $BACKUP_DIR -Filter "wiredpart_*.db" |
    Sort-Object CreationTime -Descending |
    Select-Object -Skip 30
if ($old) {
    $old | Remove-Item
    Write-Host "Cleaned up $($old.Count) old backup(s)." -ForegroundColor Gray
}
