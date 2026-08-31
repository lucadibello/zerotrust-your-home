#!/bin/bash

# Setup or remove cronjob for automatic system backup and prune
# Backup: Runs at 00:00 daily to perform system backup (Local + Cloud)
# Prune: Runs at 03:00 weekly (every Sunday) to prune old snapshots and reclaim disk space

trap "exit" INT

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BACKUP_CRON_COMMENT="# zerotrust-backup-daily"
BACKUP_CRON_TIME="0 0 * * *"
BACKUP_CRON_CMD="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:\$PATH cd $PROJECT_DIR && make backup >> /var/log/zerotrust-backup.log 2>&1"

PRUNE_CRON_COMMENT="# zerotrust-backup-prune"
PRUNE_CRON_TIME="0 3 * * 0"
PRUNE_CRON_CMD="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:\$PATH cd $PROJECT_DIR && make backup-prune >> /var/log/zerotrust-backup-prune.log 2>&1"

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
    echo "==========================================="
    echo "       ZeroTrust Backup Cron Status        "
    echo "==========================================="
    
    # Check daily backup cronjob (also checks legacy comment # zerotrust-backup-full)
    if crontab -l 2>/dev/null | grep -qE "(zerotrust-backup-daily|zerotrust-backup-full)"; then
        echo "[*] Daily Backup cronjob: ENABLED"
        echo "    Schedule: Daily at 00:00"
        echo "    Log file: /var/log/zerotrust-backup.log"
        crontab -l 2>/dev/null | grep -E -A1 "(zerotrust-backup-daily|zerotrust-backup-full)" | sed 's/^/      /'
    else
        echo "[*] Daily Backup cronjob: DISABLED"
    fi

    echo ""
    # Check weekly prune cronjob
    if crontab -l 2>/dev/null | grep -q "$PRUNE_CRON_COMMENT"; then
        echo "[*] Weekly Prune cronjob: ENABLED"
        echo "    Schedule: Weekly on Sunday at 03:00"
        echo "    Log file: /var/log/zerotrust-backup-prune.log"
        crontab -l 2>/dev/null | grep -A1 "$PRUNE_CRON_COMMENT" | sed 's/^/      /'
    else
        echo "[*] Weekly Prune cronjob: DISABLED"
    fi
    echo "==========================================="
}

enable_backup_cron() {
    ensure_cron_installed
    if crontab -l 2>/dev/null | grep -qE "(zerotrust-backup-daily|zerotrust-backup-full)"; then
        echo "[*] Daily backup cronjob already exists. No changes made."
        return 0
    fi

    touch /var/log/zerotrust-backup.log 2>/dev/null || sudo touch /var/log/zerotrust-backup.log

    (crontab -l 2>/dev/null; echo "$BACKUP_CRON_COMMENT"; echo "$BACKUP_CRON_TIME $BACKUP_CRON_CMD") | crontab -

    if [ $? -eq 0 ]; then
        echo "[OK] Daily Backup cronjob enabled."
        echo "     Schedule: Daily at 00:00"
        echo "     Log file: /var/log/zerotrust-backup.log"
    else
        echo "[ERROR] Failed to add daily backup cronjob."
        exit 1
    fi
}

disable_backup_cron() {
    if ! crontab -l 2>/dev/null | grep -qE "(zerotrust-backup-daily|zerotrust-backup-full)"; then
        echo "[*] No daily backup cronjob found. Nothing to disable."
        return 0
    fi

    crontab -l 2>/dev/null | grep -vE "(zerotrust-backup-daily|zerotrust-backup-full)" | grep -v "make backup >>" | crontab -

    if [ $? -eq 0 ]; then
        echo "[OK] Daily Backup cronjob disabled."
    else
        echo "[ERROR] Failed to remove daily backup cronjob."
        exit 1
    fi
}

enable_prune_cron() {
    ensure_cron_installed
    if crontab -l 2>/dev/null | grep -q "$PRUNE_CRON_COMMENT"; then
        echo "[*] Weekly prune cronjob already exists. No changes made."
        return 0
    fi

    touch /var/log/zerotrust-backup-prune.log 2>/dev/null || sudo touch /var/log/zerotrust-backup-prune.log

    (crontab -l 2>/dev/null; echo "$PRUNE_CRON_COMMENT"; echo "$PRUNE_CRON_TIME $PRUNE_CRON_CMD") | crontab -

    if [ $? -eq 0 ]; then
        echo "[OK] Weekly Prune cronjob enabled."
        echo "     Schedule: Weekly on Sunday at 03:00"
        echo "     Log file: /var/log/zerotrust-backup-prune.log"
    else
        echo "[ERROR] Failed to add weekly prune cronjob."
        exit 1
    fi
}

disable_prune_cron() {
    if ! crontab -l 2>/dev/null | grep -q "$PRUNE_CRON_COMMENT"; then
        echo "[*] No weekly prune cronjob found. Nothing to disable."
        return 0
    fi

    crontab -l 2>/dev/null | grep -v "$PRUNE_CRON_COMMENT" | grep -v "make backup-prune >>" | crontab -

    if [ $? -eq 0 ]; then
        echo "[OK] Weekly Prune cronjob disabled."
    else
        echo "[ERROR] Failed to remove weekly prune cronjob."
        exit 1
    fi
}

enable_all() {
    enable_backup_cron
    echo ""
    enable_prune_cron
}

disable_all() {
    disable_backup_cron
    echo ""
    disable_prune_cron
}

case "${1:-}" in
    enable|enable-backup)
        enable_backup_cron
        ;;
    disable|disable-backup)
        disable_backup_cron
        ;;
    enable-prune)
        enable_prune_cron
        ;;
    disable-prune)
        disable_prune_cron
        ;;
    enable-all)
        enable_all
        ;;
    disable-all)
        disable_all
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {enable|disable|enable-prune|disable-prune|enable-all|disable-all|status}"
        echo ""
        echo "Commands:"
        echo "  enable        - Add cronjob to run backup daily at 00:00"
        echo "  disable       - Remove the daily backup cronjob"
        echo "  enable-prune  - Add cronjob to prune old backups weekly (Sunday 03:00)"
        echo "  disable-prune - Remove the weekly prune cronjob"
        echo "  enable-all    - Enable both daily backup and weekly prune cronjobs"
        echo "  disable-all   - Remove all backup & prune cronjobs"
        echo "  status        - Show current cronjob status"
        exit 1
        ;;
esac
