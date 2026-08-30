#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env file
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi

cd "$PROJECT_DIR" || exit 1

RESTIC_COMPOSE="$PROJECT_DIR/composes/backup/docker-compose.yaml"
if [ ! -f "$RESTIC_COMPOSE" ]; then
  RESTIC_COMPOSE="$PROJECT_DIR/composes/restic.docker-compose.yaml"
fi

# Build list of active compose files to manage during backup
COMPOSE_ARGS=$(bash "$PROJECT_DIR/scripts/get_docker_compose_files.sh")

# Cleanup function to ensure containers restart and maintenance mode is off
cleanup() {
  echo "[!] Script interrupted or failed. Running cleanup..."

  # Restart containers if they were stopped
  echo "[*] Restarting containers (Emergency)..."
  sudo docker compose $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" start 2>/dev/null || true

  # Start Nextcloud AIO sibling containers explicitly
  if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
    echo "[*] Starting Nextcloud AIO containers (Emergency)..."
    sudo docker start nextcloud-aio-database nextcloud-aio-redis nextcloud-aio-apache nextcloud-aio-nextcloud 2>/dev/null || true
    sleep 10
  fi

  # Disable Maintenance Mode for Nextcloud
  if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ] && docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
    echo "[*] Disabling Nextcloud Maintenance Mode (Emergency)..."
    docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --off 2>/dev/null || true
  fi
}

# Function to restart containers and disable maintenance mode normally
start_services() {
  echo "[*] Restarting containers..."
  sudo docker compose $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" start

  if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
    echo "[*] Starting Nextcloud AIO containers..."
    sudo docker start nextcloud-aio-database nextcloud-aio-redis nextcloud-aio-apache nextcloud-aio-nextcloud 2>/dev/null || true
    
    echo "[*] Waiting for Nextcloud container to start..."
    ATTEMPTS=0
    while ! docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; do
      if [ $ATTEMPTS -ge 30 ]; then
        echo "[WARNING] Nextcloud container failed to start within timeout. Cannot disable maintenance mode."
        break
      fi
      sleep 2
      ATTEMPTS=$((ATTEMPTS + 1))
    done

    if docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
      echo "[*] Disabling Nextcloud Maintenance Mode..."
      sleep 5
      docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --off 2>/dev/null || true
    fi
  fi
}

# Register cleanup trap
trap cleanup EXIT INT TERM

# Check for required environment variables
if [ -z "${NEXTCLOUD_DATADIR:-}" ] || [ -z "${LOCAL_BACKUP_DIR:-}" ]; then
  echo "[ERROR] Required environment variables NEXTCLOUD_DATADIR or LOCAL_BACKUP_DIR are not set."
  echo "        Please check your .env file."
  exit 1
fi

# Run Immich backup if enabled (requires Immich to be running)
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
  echo "[*] Running Immich export..."
  bash "$PROJECT_DIR/scripts/backups/backup-immich.sh"
fi

# Enable Maintenance Mode for Nextcloud
if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ] && docker ps -q -f name=nextcloud-aio-nextcloud 2>/dev/null | grep -q .; then
  echo "[*] Enabling Nextcloud Maintenance Mode..."
  docker exec --user www-data nextcloud-aio-nextcloud php /var/www/html/occ maintenance:mode --on
fi

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
bash "$PROJECT_DIR/scripts/backups/dump-databases.sh"

echo "[*] Stopping containers for consistent state..."
sudo docker compose $COMPOSE_ARGS --env-file "$PROJECT_DIR/.env" stop

# Explicitly stop Nextcloud AIO sibling containers if they are running
if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
  echo "[*] Ensuring Nextcloud AIO containers are stopped..."
  sudo docker stop nextcloud-aio-database nextcloud-aio-nextcloud nextcloud-aio-redis nextcloud-aio-apache 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Restart services NOW after securing database dumps
# ------------------------------------------------------------------------------
echo "[*] Database dumps secured. Restarting services to minimize downtime..."
start_services

# Helper function for Telegram notifications
send_telegram() {
  local message="$1"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    curl -s -X POST -H 'Content-Type: application/json' \
      -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\",\"text\": \"${message}\"}" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null || true
  fi
}

echo "[*] Initializing repository if needed..."
# 1. Local Repository Initialization
if ! sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic -r /repos/local/restic snapshots >/dev/null 2>&1; then
  echo "[*] Local Repository not found. Initializing..."
  sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
    exec backup restic -r /repos/local/restic init
fi

# 2. Cloud Repository Initialization
if ! sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" exec backup restic snapshots >/dev/null 2>&1; then
  echo "[*] Cloud Repository not found. Initializing..."
  sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
    exec backup restic init
fi

echo "[*] Running backup (Services are ONLINE)..."
BACKUP_EXIT_CODE=0

# 1. Local Backup
echo "[*] >> Starting Local Backup (Live System)..."
echo "[!] NOTE: Raw database files in /var/lib/docker/volumes may be inconsistent."
echo "[!]       You MUST use the SQL dumps in backups/db-dumps/ for database recovery."
sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec backup restic -r /repos/local/restic backup /mnt/backup --host docker --tag backup --exclude='*.tmp' --verbose
LOCAL_EXIT=$?

# 2. Cloud Backup (Copy from Local Repo)
echo "[*] >> Starting Cloud Backup (Copying from Local Repo)..."
sudo docker compose -f "$RESTIC_COMPOSE" --env-file "$PROJECT_DIR/.env" \
  exec -e RESTIC_FROM_PASSWORD="${RESTIC_PASSWORD}" backup restic copy --from-repo /repos/local/restic
CLOUD_EXIT=$?

if [ $LOCAL_EXIT -eq 0 ] && [ $CLOUD_EXIT -eq 0 ]; then
  echo "[OK] All backups completed successfully"
  send_telegram "✅ Docker volumes backup to Local Disk AND Cloud completed successfully!"
elif [ $LOCAL_EXIT -ne 0 ] && [ $CLOUD_EXIT -ne 0 ]; then
  echo "[ERROR] BOTH backups failed!"
  BACKUP_EXIT_CODE=1
  send_telegram "❌ CRITICAL: Both Local and Cloud backups failed! Check logs immediately."
elif [ $LOCAL_EXIT -ne 0 ]; then
  echo "[WARNING] Local backup failed, but Cloud backup succeeded (somehow?)."
  BACKUP_EXIT_CODE=1
  send_telegram "⚠️ Local backup failed. Check logs."
else
  echo "[WARNING] Cloud backup/copy failed, but Local backup succeeded."
  BACKUP_EXIT_CODE=1
  send_telegram "⚠️ Cloud backup upload failed (Local copy is SAFE). Check logs."
fi

# 3. Prune Old Backups
if [ $BACKUP_EXIT_CODE -eq 0 ]; then
  echo "[*] >> Pruning old snapshots to free up space..."
  bash "$PROJECT_DIR/scripts/backups/prune.sh"
fi

# Unset trap before exiting successfully
trap - EXIT INT TERM

exit $BACKUP_EXIT_CODE
