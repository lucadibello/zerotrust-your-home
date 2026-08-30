#!/bin/bash
set -uo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env file
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Run Immich backup if enabled (requires Immich to be running)
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
    echo "[*] Running Immich export..."
    bash "$PROJECT_DIR/scripts/backups/backup-immich.sh"
fi

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
bash "$PROJECT_DIR/scripts/backups/dump-databases.sh"

echo "[OK] Backup data exported successfully. Restic will include DB dumps in next scheduled backup."
