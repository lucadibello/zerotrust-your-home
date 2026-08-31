#!/bin/bash
set -uo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

# Run Immich backup if enabled (requires Immich to be running)
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
    echo "[*] Running Immich export..."
    bash "$PROJECT_DIR/scripts/backups/backup-immich.sh"
fi

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
bash "$PROJECT_DIR/scripts/backups/dump-databases.sh"

echo "[OK] Backup data exported successfully. Restic will include DB dumps in next scheduled backup."
