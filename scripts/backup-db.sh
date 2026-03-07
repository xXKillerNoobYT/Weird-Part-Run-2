#!/bin/bash
# Wired-Part Database Backup Script (Mac/Linux)
# ===============================================
# Creates a timestamped copy of the SQLite database.
# Keeps the last 30 backups, deletes older ones.
#
# Usage: chmod +x scripts/backup-db.sh && ./scripts/backup-db.sh
# Schedule: crontab -e → 0 0 * * * /path/to/scripts/backup-db.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="$ROOT/backend/wiredpart.db"
BACKUP_DIR="$ROOT/backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M")

# Check if using custom DB path from .env
if [ -f "$ROOT/.env" ]; then
    CUSTOM_PATH=$(grep "^DATABASE_PATH=" "$ROOT/.env" | cut -d= -f2 | tr -d ' ')
    if [ -n "$CUSTOM_PATH" ] && [ -f "$CUSTOM_PATH" ]; then
        DB="$CUSTOM_PATH"
    fi
fi

if [ ! -f "$DB" ]; then
    echo "ERROR: Database not found at $DB"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

cp "$DB" "$BACKUP_DIR/wiredpart_$TIMESTAMP.db"
SIZE=$(du -h "$BACKUP_DIR/wiredpart_$TIMESTAMP.db" | cut -f1)
echo "Backup saved: wiredpart_$TIMESTAMP.db ($SIZE)"

# Keep only last 30 backups
cd "$BACKUP_DIR"
ls -t wiredpart_*.db 2>/dev/null | tail -n +31 | xargs -r rm -f
REMAINING=$(ls wiredpart_*.db 2>/dev/null | wc -l)
echo "Total backups: $REMAINING"
