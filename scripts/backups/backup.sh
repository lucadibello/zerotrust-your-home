#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$PROJECT_DIR/scripts/common.sh" ]; then
    source "$PROJECT_DIR/scripts/common.sh"
    load_env "$PROJECT_DIR/.env"
fi

if ! command -v log >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fi

log "[*] Triggering manual backup via Restic container..."

# Ensure the container is running
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$PROJECT_DIR/composes/backup/docker-compose.yaml" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

# Execute the backup script inside the mazzolino/restic container
# This will execute PRE_COMMANDS, restic backup, and POST_COMMANDS automatically.
if docker exec restic-backup /bin/sh -c "backup"; then
    log "[OK] Manual backup triggered successfully."
else
    # If "backup" script is not available, we can fallback to just running the pre-hooks and restic manually:
    log "[*] Falling back to manual hook execution..."
    docker exec restic-backup bash /mnt/backup/project/scripts/backups/container-pre-backup.sh
    docker exec restic-backup restic -r /repos/local/restic backup /mnt/backup --host docker --tag backup --exclude='*.tmp' --exclude-file=/tmp/excludes.txt
    if [ $? -eq 0 ]; then
        docker exec restic-backup bash /mnt/backup/project/scripts/backups/container-post-backup.sh success
    else
        docker exec restic-backup bash /mnt/backup/project/scripts/backups/container-post-backup.sh failure
    fi
fi
