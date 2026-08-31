#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load common features and .env
source "$PROJECT_DIR/scripts/common.sh"
load_env "$PROJECT_DIR/.env"

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"
if [ ! -f "$RESTIC_COMPOSE" ]; then
    RESTIC_COMPOSE="$PROJECT_DIR/composes/restic.docker-compose.yaml"
fi

# Ensure backup container is running
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

LOCAL_REPO="/repos/local/restic"
if docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -T backup test -f /repos/local/config 2>/dev/null; then
    LOCAL_REPO="/repos/local"
fi

echo "[*] Removing stale locks (Local: $LOCAL_REPO)..."
docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -T backup restic -r "$LOCAL_REPO" unlock
LOCAL_EXIT=$?

CLOUD_EXIT=0
IS_RCLONE=false
if [[ "${RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
    IS_RCLONE=true
fi

if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
    echo "[*] Cloud unlock skipped: Rclone is not configured."
else
    echo "[*] Removing stale locks (Cloud)..."
    docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
      exec -T backup restic unlock
    CLOUD_EXIT=$?
fi

if [ $LOCAL_EXIT -eq 0 ] && [ $CLOUD_EXIT -eq 0 ]; then
  echo "[OK] Repositories unlocked successfully."
else
  echo "[ERROR] Unlock failed (local=$LOCAL_EXIT, cloud=$CLOUD_EXIT)."
fi

exit $(( LOCAL_EXIT || CLOUD_EXIT ))
