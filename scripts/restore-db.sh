#!/bin/bash
# Wired-Part Database Restore Script (Mac/Linux)
# =============================================
# Restores a SQLite database from a backup file.
#
# Usage:
#   bash scripts/restore-db.sh                           # interactive pick
#   bash scripts/restore-db.sh backups/wiredpart_2026-03-06_0000.db

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="$ROOT/backend/wiredpart.db"
BACKUP_DIR="$ROOT/backups"

# Check .env for custom DB path
if [ -f "$ROOT/.env" ]; then
    custom=$(grep "^DATABASE_PATH=" "$ROOT/.env" | cut -d= -f2 | tr -d ' ')
    if [ -n "$custom" ]; then DB="$custom"; fi
fi

BACKUP_FILE="$1"

# If no backup specified, list and prompt
if [ -z "$BACKUP_FILE" ]; then
    backups=$(ls -1t "$BACKUP_DIR"/wiredpart_*.db 2>/dev/null || true)
    if [ -z "$backups" ]; then
        echo "ERROR: No backups found in $BACKUP_DIR"
        exit 1
    fi

    echo ""
    echo "Available backups:"
    i=1
    while IFS= read -r f; do
        size=$(du -h "$f" | cut -f1)
        name=$(basename "$f")
        echo "  [$i] $name  ($size)  $(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f" 2>/dev/null || stat -c '%y' "$f" 2>/dev/null | cut -c1-16)"
        i=$((i+1))
        if [ $i -gt 10 ]; then break; fi
    done <<< "$backups"

    printf "\nEnter number to restore (or 'q' to cancel): "
    read -r choice
    if [ "$choice" = "q" ] || [ -z "$choice" ]; then exit 0; fi

    BACKUP_FILE=$(echo "$backups" | sed -n "${choice}p")
    if [ -z "$BACKUP_FILE" ]; then
        echo "Invalid choice."
        exit 1
    fi
fi

# Resolve relative path
if [[ "$BACKUP_FILE" != /* ]]; then
    BACKUP_FILE="$ROOT/$BACKUP_FILE"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo ""
echo "=== Wired-Part Database Restore ==="
echo "Source:  $BACKUP_FILE"
echo "Target:  $DB"
printf "\nThis will REPLACE the current database. Continue? (y/N): "
read -r confirm
if [ "$confirm" != "y" ]; then
    echo "Cancelled."
    exit 0
fi

# 1. Safety backup of current DB
safety="$BACKUP_DIR/wiredpart_pre-restore_$(date +%Y-%m-%d_%H%M%S).db"
if [ -f "$DB" ]; then
    cp "$DB" "$safety"
    echo "Safety backup created: $safety"
fi

# 2. Stop server if running
if pgrep -f "uvicorn.*app.main" > /dev/null 2>&1; then
    echo "Stopping server..."
    pkill -f "uvicorn.*app.main" || true
    sleep 2
fi

# 3. Restore
cp "$BACKUP_FILE" "$DB"
size=$(du -h "$DB" | cut -f1)
echo ""
echo "Database restored successfully ($size)."
echo "Run 'bash scripts/start-server.sh' to restart the server."
