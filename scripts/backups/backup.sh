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

# Dump databases (requires containers to be running)
echo "[*] Dumping databases..."
bash ../scripts/backups/dump-databases.sh

echo "[*] Stopping containers for backup..."
sudo docker compose $COMPOSE_FILES --env-file ../.env stop

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
if ! sudo docker compose -f restic.docker-compose.yaml --env-file ../.env exec backup restic snapshots >/dev/null 2>&1; then
  echo "[*] Repository not found. Initializing..."
  sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
    exec backup restic init
fi

echo "[*] Running backup..."
sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic backup /mnt/backup --host docker --tag backup --exclude='*.tmp' --verbose

BACKUP_EXIT_CODE=$?

if [ $BACKUP_EXIT_CODE -eq 0 ]; then
  echo "[OK] Backup completed successfully"
  send_telegram "✅ Docker volumes backup completed successfully!"
else
  echo "[ERROR] Backup failed with exit code $BACKUP_EXIT_CODE"
  send_telegram "❌ An error occurred during Docker volumes backup! Check Restic logs for more details."
fi

# Restart all containers
echo "[*] Restarting containers..."
sudo docker compose $COMPOSE_FILES --env-file ../.env start


cd ..

exit $BACKUP_EXIT_CODE
