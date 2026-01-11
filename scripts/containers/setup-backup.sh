#!/bin/bash
trap "exit" INT

# Load environment variables
set -a
source .env
set +a

# Skip if Backup is not enabled
if [ "$ENABLE_BACKUP" != "true" ]; then
  echo "[*] Backup is disabled, skipping setup..."
  exit 0
fi

# Create required directories for database dumps
mkdir -p ./composes/backups/db-dumps || true

# Enable the backup export cronjob (runs daily at 23:30 before restic's midnight backup)
echo "[*] Setting up backup export cronjob..."
bash ./scripts/backups/setup-backup-cron.sh enable

echo "[OK] Backup setup completed"
