#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-/mnt/backup/project}"
if [ ! -d "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ -f "$PROJECT_DIR/scripts/common.sh" ]; then
    source "$PROJECT_DIR/scripts/common.sh"
fi

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

STATUS="$1"

log "[*] Running POST_COMMANDS for prune with status: $STATUS"

if [ "$STATUS" = "success" ]; then
    if [[ "${CLOUD_RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
        rclone_conf="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}"
        if [ ! -f "$rclone_conf" ]; then
            if [ -f "/mnt/backup/project/config/rclone/rclone.conf" ]; then
                mkdir -p /root/.config/rclone
                cp -f "/mnt/backup/project/config/rclone/rclone.conf" /root/.config/rclone/rclone.conf
                rclone_conf="/root/.config/rclone/rclone.conf"
            elif [ -f "/config/rclone/rclone.conf" ]; then
                rclone_conf="/config/rclone/rclone.conf"
            fi
        fi
        export RCLONE_CONFIG="$rclone_conf"

        if [ ! -f "$rclone_conf" ]; then
            log "[ERROR] Rclone config file not found ($rclone_conf). Cloud prune skipped."
        else
            log "[*] Pruning cloud repository..."
            export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}"
            if restic -r "${CLOUD_RESTIC_REPOSITORY}" forget --prune ${RESTIC_FORGET_ARGS:---keep-last 3 --keep-daily 3 --keep-weekly 2 --keep-monthly 1}; then
                log "[OK] Cloud repository pruned successfully."
            else
                log "[!] Cloud repository prune failed."
            fi
        fi
    fi
    log "[*] Sending notification: Prune Successful"
    curl -s -H "Title: Prune Successful" -H "Tags: broom,white_check_mark" -d "Local and Cloud repositories pruned successfully." "${NTFY_URL%/}/${NTFY_TOPIC}"
else
    log "[ERROR] Sending notification: Prune Failed"
    curl -s -H "Title: Prune Failed" -H "Priority: high" -H "Tags: broom,warning" -d "Automated prune failed!" "${NTFY_URL%/}/${NTFY_TOPIC}"
fi

log "[*] Post-prune tasks completed."
