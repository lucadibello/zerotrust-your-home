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

log "[*] Running POST_COMMANDS inside Restic container with status: $STATUS"

# Copy to Cloud
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
            log "[ERROR] Rclone config file not found ($rclone_conf). Cloud copy cannot proceed."
            log "[!] Please configure rclone on the host using 'make backup-configure'."
            STATUS="success_but_copy_failed"
        else
            log "[*] Copying local snapshot to cloud repository ($CLOUD_RESTIC_REPOSITORY)..."
            export RESTIC_FROM_PASSWORD="$RESTIC_PASSWORD"
            if restic -r "$CLOUD_RESTIC_REPOSITORY" copy --from-repo /repos/local/restic; then
                log "[OK] Cloud repository copy completed successfully."
            else
                log "[!] Copy failed! Will notify."
                STATUS="success_but_copy_failed"
            fi
        fi
    fi
fi

# Send Ntfy
if [ -n "${NTFY_TOPIC:-}" ]; then
    NTFY_BASE="${NTFY_URL:-https://ntfy.home.lucadibello.ch}"
    NTFY_ENDPOINT="${NTFY_BASE%/}/${NTFY_TOPIC}"
    
    if [ "$STATUS" = "success" ]; then
        log "[*] Sending notification: Backup Successful"
        curl -s -H "Title: Backup Successful" -H "Tags: white_check_mark,floppy_disk" -d "Local and Cloud backup completed!" "$NTFY_ENDPOINT"
    elif [ "$STATUS" = "success_but_copy_failed" ]; then
        log "[WARNING] Sending notification: Backup Warning (Cloud copy failed)"
        curl -s -H "Title: Backup Warning" -H "Priority: high" -H "Tags: warning,floppy_disk" -d "Local backup success, but Cloud copy failed!" "$NTFY_ENDPOINT"
    else
        log "[ERROR] Sending notification: Backup Failed ($STATUS)"
        curl -s -H "Title: Backup Failed" -H "Priority: high" -H "Tags: warning,x,floppy_disk" -d "Backup failed during local snapshot ($STATUS)!" "$NTFY_ENDPOINT"
    fi
fi

log "[*] Post-backup tasks completed."
