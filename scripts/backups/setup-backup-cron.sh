#!/bin/bash

# Setup or remove cronjob for automatic system backup
# Runs at 00:00 daily to perform full backup (Local + Cloud)
# Includes database dumps and Immich exports automatically

trap "exit" INT

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRON_COMMENT="# zerotrust-backup-full"
CRON_TIME="0 0 * * *"
CRON_CMD="cd $PROJECT_DIR && make backup >> /var/log/zerotrust-backup.log 2>&1"

ensure_cron_installed() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "[*] crontab not found. Installing cron package..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cron
            sudo systemctl enable cron 2>/dev/null || true
            sudo systemctl start cron 2>/dev/null || true
        else
            echo "[ERROR] crontab command not found. Please install cron."
            exit 1
        fi
    fi
}

show_status() {
    ensure_cron_installed
    if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        echo "[*] Full Backup cronjob is ENABLED"
        echo "    Schedule: Daily at 00:00"
        echo "    Log file: /var/log/zerotrust-backup.log"
        crontab -l 2>/dev/null | grep -A1 "$CRON_COMMENT"
    else
        echo "[*] Backup export cronjob is DISABLED"
    fi
}

enable_cron() {
    ensure_cron_installed
    if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        echo "[*] Cronjob already exists. No changes made."
        return 0
    fi


    # Create log file (will be owned by whoever runs the cron - typically root for system tasks)
    touch /var/log/zerotrust-backup.log 2>/dev/null || sudo touch /var/log/zerotrust-backup.log

    # Add cronjob (goes to root's crontab when run via sudo, which is correct for system backups)
    (crontab -l 2>/dev/null; echo "$CRON_COMMENT"; echo "$CRON_TIME $CRON_CMD") | crontab -

    if [ $? -eq 0 ]; then
        echo "[OK] Full Backup cronjob enabled."
        echo "     Schedule: Daily at 00:00"
        echo "     Log file: /var/log/zerotrust-backup.log"
    else
        echo "[ERROR] Failed to add cronjob."
        exit 1
    fi
}

disable_cron() {
    if ! crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        echo "[*] No cronjob found. Nothing to disable."
        return 0
    fi

    # Remove cronjob (both comment and command lines)
    crontab -l 2>/dev/null | grep -v "$CRON_COMMENT" | grep -v "$CRON_CMD" | crontab -

    if [ $? -eq 0 ]; then
        echo "[OK] Full Backup cronjob disabled."
    else
        echo "[ERROR] Failed to remove cronjob."
        exit 1
    fi
}

case "${1:-}" in
    enable)
        enable_cron
        ;;
    disable)
        disable_cron
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        echo ""
        echo "Commands:"
        echo "  enable   - Add cronjob to run full backup daily at 00:00"
        echo "  disable  - Remove the full backup cronjob"
        echo "  status   - Show current cronjob status"
        exit 1
        ;;
esac
