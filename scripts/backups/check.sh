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
sudo docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" up -d backup >/dev/null 2>&1 || true

LOCAL_REPO="/repos/local/restic"
if sudo docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -T backup test -f /repos/local/config 2>/dev/null; then
    LOCAL_REPO="/repos/local"
fi

echo "[*] Running integrity check (Local: $LOCAL_REPO - 10% of data)..."
sudo docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -T backup restic -r "$LOCAL_REPO" check --read-data-subset=10%
LOCAL_EXIT=$?

CLOUD_EXIT=0
IS_RCLONE=false
if [[ "${RESTIC_REPOSITORY:-}" =~ ^rclone: ]]; then
    IS_RCLONE=true
fi

if [ "$IS_RCLONE" = "true" ] && [ ! -f "$PROJECT_DIR/config/rclone/rclone.conf" ]; then
    echo "[*] Cloud integrity check skipped: Rclone is not configured."
else
    echo "[*] Running integrity check (Cloud - 10% of data)..."
    sudo docker compose --project-name zerotrust-your-home --project-directory "$PROJECT_DIR" -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
      exec -T backup restic check --read-data-subset=10%
    CLOUD_EXIT=$?
fi

if [ $LOCAL_EXIT -eq 0 ] && [ $CLOUD_EXIT -eq 0 ]; then
  echo "[OK] Check completed successfully"
  send_ntfy "Backup Integrity OK" "Integrity check passed for all repositories." "white_check_mark,mag" "low"
else
  echo "[ERROR] Check failed (local=$LOCAL_EXIT, cloud=$CLOUD_EXIT)"
  send_ntfy "Backup Integrity Check Failed" "CRITICAL: Backup integrity check failed (local=$LOCAL_EXIT, cloud=$CLOUD_EXIT)!" "warning,x,mag" "urgent"
fi

exit $(( LOCAL_EXIT || CLOUD_EXIT ))
