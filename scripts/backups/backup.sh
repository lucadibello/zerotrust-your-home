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

FORCE_FULL_ENV=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full|-f)
      FORCE_FULL_ENV="-e FORCE_FULL=true"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--full|-f]"
      echo ""
      echo "Options:"
      echo "  --full, -f    Force a full backup (full Immich photo export + Restic snapshot)"
      echo "  --help, -h    Show this help message"
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

log "[*] Triggering manual backup via Restic container..."

# Ensure the container is running
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$PROJECT_DIR/composes/backup/docker-compose.yaml" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

tmp_log=$(mktemp)
trap 'rm -f "$tmp_log"' EXIT

# Execute the backup script inside the mazzolino/restic container
# This will execute PRE_COMMANDS, restic backup, and POST_COMMANDS automatically.
if docker exec ${FORCE_FULL_ENV:-} restic-backup /bin/sh -c "backup" 2>&1 | tee "$tmp_log"; then
    log "[OK] Manual backup completed successfully."
else
    exit_code=$?
    if grep -qi "already running" "$tmp_log"; then
        log "[*] A backup is already in progress inside the Restic container. Skipping duplicate execution."
        exit 0
    elif grep -qi "not found" "$tmp_log"; then
        # If "backup" script is not available, fallback to manual hook execution:
        log "[*] 'backup' command not found in container. Falling back to manual hook execution..."
        docker exec ${FORCE_FULL_ENV:-} restic-backup bash /mnt/backup/project/scripts/backups/container-pre-backup.sh
        docker exec restic-backup restic -r /repos/local/restic backup /mnt/backup --host docker --tag backup --exclude='*.tmp' --exclude-file=/tmp/excludes.txt
        if [ $? -eq 0 ]; then
            docker exec restic-backup bash /mnt/backup/project/scripts/backups/container-post-backup.sh success
        else
            docker exec restic-backup bash /mnt/backup/project/scripts/backups/container-post-backup.sh failure
            exit 1
        fi
    else
        log "[ERROR] Backup failed inside Restic container (exit code $exit_code)."
        exit "$exit_code"
    fi
fi
