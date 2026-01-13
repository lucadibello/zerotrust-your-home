#!/bin/bash

trap "exit" INT

# Load .env file
set -a
source .env
set +a

cd composes || exit 1

# Build list of compose files to stop (excluding restic)
COMPOSE_FILES=""

# Core services
[ -f dns.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f dns.docker-compose.yaml"
[ -f traefik.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f traefik.docker-compose.yaml"
[ -f prometheus.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f prometheus.docker-compose.yaml"
[ -f loki.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f loki.docker-compose.yaml"
[ -f uptimekuma.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f uptimekuma.docker-compose.yaml"
[ -f watchtower.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f watchtower.docker-compose.yaml"

# Optional services
[ "$ENABLE_HOME_AUTOMATION" = "true" ] && [ -f home.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f home.docker-compose.yaml"
[ "$ENABLE_VAULTWARDEN" = "true" ] && [ -f vaultwarden.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f vaultwarden.docker-compose.yaml"
[ "$ENABLE_NEXTCLOUD" = "true" ] && [ -f nextcloud.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f nextcloud.docker-compose.yaml"
[ "$ENABLE_PORTAINER" = "true" ] && [ -f portainer.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f portainer.docker-compose.yaml"
[ "$ENABLE_IMMICH" = "true" ] && [ -f immich.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f immich.docker-compose.yaml"
[ "$ENABLE_SEARXNG" = "true" ] && [ -f searxng.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f searxng.docker-compose.yaml"
[ "$ENABLE_MINECRAFT" = "true" ] && [ -f mcserver.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f mcserver.docker-compose.yaml"

# Run Immich backup if enabled (requires Immich to be running)
if [ "$ENABLE_IMMICH" = "true" ]; then
    echo "[*] Running Immich export..."
    bash ../scripts/backups/backup-immich.sh
fi

# Enable Maintenance Mode for Nextcloud
if [ "$ENABLE_NEXTCLOUD" = "true" ] && [ "$(docker ps -q -f name=nextcloud-aio-nextcloud)" ]; then
    echo "[*] Enabling Nextcloud Maintenance Mode..."
    docker exec --user www-data nextcloud-aio-nextcloud php occ maintenance:mode --on
fi

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
bash ../scripts/backups/dump-databases.sh

echo "[*] Stopping containers for backup..."
sudo docker-compose "$COMPOSE_FILES" --env-file ../.env stop

# Explicitly stop Nextcloud AIO sibling containers if they are running
# (Master container stop might not be instant or might restart them if not careful)
if [ "$ENABLE_NEXTCLOUD" = "true" ]; then
    echo "[*] Ensuring Nextcloud AIO containers are stopped..."
    sudo docker stop nextcloud-aio-database nextcloud-aio-nextcloud nextcloud-aio-redis nextcloud-aio-apache 2>/dev/null || true
fi

# Helper function for Telegram notifications
send_telegram() {
  local message="$1"
  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    curl -s -X POST -H 'Content-Type: application/json' \
      -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\",\"text\": \"${message}\"}" \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null
  fi
}

echo "[*] Initializing repository if needed..."
# 1. Local Repository Initialization
if ! sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env exec backup restic -r /repos/local/restic snapshots >/dev/null 2>&1; then
  echo "[*] Local Repository not found. Initializing..."
  sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
    exec backup restic -r /repos/local/restic init
fi

# 2. Cloud Repository Initialization
if ! sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env exec backup restic snapshots >/dev/null 2>&1; then
  echo "[*] Cloud Repository not found. Initializing..."
  sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
    exec backup restic init
fi

echo "[*] Running backup..."
BACKUP_EXIT_CODE=0

# 1. Local Backup
echo "[*] >> Starting Local Backup (Fast)..."
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic -r /repos/local/restic backup /mnt/backup --host docker --tag backup --exclude='*.tmp' --verbose
LOCAL_EXIT=$?

# 2. Cloud Backup
echo "[*] >> Starting Cloud Backup (Google Drive)..."
sudo docker-compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic backup /mnt/backup --host docker --tag backup --exclude='*.tmp' --verbose
CLOUD_EXIT=$?

if [ $LOCAL_EXIT -eq 0 ] && [ $CLOUD_EXIT -eq 0 ]; then
  echo "[OK] All backups completed successfully"
  send_telegram "✅ Docker volumes backup to Local Disk AND Google Drive completed successfully!"
elif [ $LOCAL_EXIT -ne 0 ] && [ $CLOUD_EXIT -ne 0 ]; then
  echo "[ERROR] BOTH backups failed!"
  BACKUP_EXIT_CODE=1
  send_telegram "❌ CRITICAL: Both Local and Cloud backups failed! Check logs immediately."
elif [ $LOCAL_EXIT -ne 0 ]; then
  echo "[WARNING] Local backup failed, but Cloud backup succeeded."
  BACKUP_EXIT_CODE=1
  send_telegram "⚠️ Local backup failed (Cloud OK). Check logs."
else
  echo "[WARNING] Cloud backup failed, but Local backup succeeded."
  BACKUP_EXIT_CODE=1
  send_telegram "⚠️ Cloud backup failed (Local OK). Check logs."
fi

# Restart all containers
echo "[*] Restarting containers..."
sudo docker-compose "$COMPOSE_FILES" --env-file ../.env start

# Disable Maintenance Mode for Nextcloud
if [ "$ENABLE_NEXTCLOUD" = "true" ]; then
    echo "[*] Waiting for Nextcloud container to start..."
    # Wait loop until container is up
    ATTEMPTS=0
    while ! docker ps -q -f name=nextcloud-aio-nextcloud >/dev/null; do
        if [ $ATTEMPTS -ge 30 ]; then
            echo "[WARNING] Nextcloud container failed to start within timeout. Cannot disable maintenance mode."
            break
        fi
        sleep 2
        ATTEMPTS=$((ATTEMPTS+1))
    done
    
    if [ "$(docker ps -q -f name=nextcloud-aio-nextcloud)" ]; then
        echo "[*] Disabling Nextcloud Maintenance Mode..."
        # Sleep a bit more to ensure PHP process is ready
        sleep 5
        docker exec --user www-data nextcloud-aio-nextcloud php occ maintenance:mode --off
    fi
fi

cd ..

exit $BACKUP_EXIT_CODE
