#!/bin/bash

# Load .env file
set -a
source .env
set +a

cd composes

# Build list of compose files to stop (excluding restic)
COMPOSE_FILES=""

# Core services
[ -f dns.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f dns.docker-compose.yaml"
[ -f traefik.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f traefik.docker-compose.yaml"
[ -f prometheus.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f prometheus.docker-compose.yaml"
[ -f loki.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f loki.docker-compose.yaml"
[ -f uptimekuma.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f uptimekuma.docker-compose.yaml"
[ -f watchtower.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f watchtower.docker-compose.yaml"

# Optional services (only include if enabled)
[ "$ENABLE_HOME_AUTOMATION" = "true" ] && [ -f home.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f home.docker-compose.yaml"
[ "$ENABLE_VAULTWARDEN" = "true" ] && [ -f vaultwarden.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f vaultwarden.docker-compose.yaml"
[ "$ENABLE_NEXTCLOUD" = "true" ] && [ -f nextcloud.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f nextcloud.docker-compose.yaml"
[ "$ENABLE_PORTAINER" = "true" ] && [ -f portainer.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f portainer.docker-compose.yaml"
[ "$ENABLE_IMMICH" = "true" ] && [ -f immich.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f immich.docker-compose.yaml"
[ "$ENABLE_SEARXNG" = "true" ] && [ -f searxng.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f searxng.docker-compose.yaml"
[ "$ENABLE_MINECRAFT" = "true" ] && [ -f mcserver.docker-compose.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f mcserver.docker-compose.yaml"

echo "[*] Stopping containers for backup..."
sudo docker compose $COMPOSE_FILES --env-file ../.env stop

# Execute backup
echo "[*] Running backup..."
sudo docker compose -f restic.docker-compose.yaml --env-file ../.env \
  exec backup restic backup /mnt/backup --host docker --tag backup

# Restart all containers
echo "[*] Restarting containers..."
sudo docker compose $COMPOSE_FILES --env-file ../.env start

# Exit
cd ..
echo "[OK] Backup completed"
