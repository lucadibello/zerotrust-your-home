#!/bin/bash
set -uo pipefail

PHASE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

if [ -f "$PROJECT_DIR/scripts/common.sh" ]; then
    source "$PROJECT_DIR/scripts/common.sh"
fi

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

case "$PHASE" in
    pre-backup)
        log "[*] Creating Home Assistant SQLite safe backup..."
        # Using homeassistant_data named volume
        docker run --rm -v homeassistant_data:/data alpine sh -c '
            apk add --no-cache sqlite >/dev/null 2>&1
            if [ -f /data/home-assistant_v2.db ]; then
                sqlite3 /data/home-assistant_v2.db ".backup /data/home-assistant_v2_backup.db"
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
        if [ -n "${RESTORE_TARGET_PATH:-}" ] && [[ ! "$RESTORE_TARGET_PATH" == *"homeassistant"* ]]; then
            exit 0
        fi
        log "[*] Restoring Home Assistant SQLite from safe backup..."
        docker run --rm -v homeassistant_data:/data alpine sh -c '
            if [ -f /data/home-assistant_v2_backup.db ]; then
                rm -f /data/home-assistant_v2.db-wal /data/home-assistant_v2.db-shm
                cp /data/home-assistant_v2_backup.db /data/home-assistant_v2.db
            fi
        '
        ;;
esac
