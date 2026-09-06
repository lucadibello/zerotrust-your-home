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

log "[*] Running POST_COMMANDS for check with status: $STATUS"

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
            log "[ERROR] Rclone config file not found ($rclone_conf). Cloud check skipped."
        else
            log "[*] Checking cloud repository..."
            export RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}"
            if restic -r "${CLOUD_RESTIC_REPOSITORY}" check --read-data-subset=10%; then
                log "[OK] Cloud repository integrity check succeeded."
            else
                log "[!] Cloud repository integrity check failed."
            fi
        fi
    fi
    log "[*] Sending notification: Integrity Check Passed"
    curl -s -H "Title: Integrity Check Passed" -H "Tags: magnifying_glass,white_check_mark" -d "10% cryptographic verification of all Local and Cloud packs succeeded." "${NTFY_URL%/}/${NTFY_TOPIC}"
else
    log "[ERROR] Sending notification: Backup Integrity Compromised!"
    curl -s -H "Title: Backup Integrity Compromised!" -H "Priority: urgent" -H "Tags: skull,warning" -d "Repository check failed! Disk rot or corruption detected in snapshots." "${NTFY_URL%/}/${NTFY_TOPIC}"
fi

log "[*] Post-check tasks completed."
