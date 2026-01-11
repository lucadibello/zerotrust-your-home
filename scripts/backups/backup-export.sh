#!/bin/bash

trap "exit" INT

# Load .env file
set -a
source .env
set +a

cd composes

# Run Immich backup if enabled (requires Immich to be running)
if [ "$ENABLE_IMMICH" = "true" ]; then
    echo "[*] Running Immich export..."
    bash ../scripts/backups/backup-immich.sh
fi

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
bash ../scripts/backups/dump-databases.sh

# Exit - restic's automatic cron will pick up the exported data at midnight
cd ..
echo "[OK] Backup data exported successfully. Restic will include DB dumps in next scheduled backup."
