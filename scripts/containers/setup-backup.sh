#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Skip if Backup is not enabled
if [ "${ENABLE_BACKUP:-true}" != "true" ]; then
  echo "[*] Backup is disabled, skipping setup..."
  exit 0
fi

# Create required directories for backup configs and database dumps
mkdir -p "$PROJECT_ROOT/composes/backup/db-dumps" \
         "$PROJECT_ROOT/config/rclone" \
         "${LOCAL_BACKUP_DIR:-/mnt/backups}" 2>/dev/null || true

# Enable the backup export cronjob
echo "[*] Setting up backup cronjob..."
bash "$PROJECT_ROOT/scripts/backups/setup-backup-cron.sh" enable

echo "[OK] Backup setup completed"
