#!/bin/bash
set -uo pipefail

PHASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

case "$PHASE" in
    pre-backup)
        echo "[*] Creating Vaultwarden SQLite safe backup..."
        # Vaultwarden volume is named vaultwarden_data
        docker run --rm -v vaultwarden_data:/data alpine sh -c '
            apk add --no-cache sqlite >/dev/null 2>&1
            if [ -f /data/db.sqlite3 ]; then
                sqlite3 /data/db.sqlite3 ".backup /data/db_backup.sqlite3"
            fi
        '
        ;;
    dump)
        ;;
    resume)
        ;;
    pre-restore)
        ;;
    post-restore)
        if [ -n "${RESTORE_TARGET_PATH:-}" ] && [[ ! "$RESTORE_TARGET_PATH" == *"vaultwarden"* ]]; then
            exit 0
        fi
        echo "[*] Restoring Vaultwarden SQLite from safe backup..."
        docker run --rm -v vaultwarden_data:/data alpine sh -c '
            if [ -f /data/db_backup.sqlite3 ]; then
                rm -f /data/db.sqlite3-wal /data/db.sqlite3-shm
                cp /data/db_backup.sqlite3 /data/db.sqlite3
            fi
        '
        ;;
esac
