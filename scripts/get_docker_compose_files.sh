#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/common.sh" ]; then
  source "$SCRIPT_DIR/common.sh"
  load_env .env
elif [ -f .env ]; then
  set -a
  source .env
  set +a
fi

FILES=""

# Helper function to find and add service compose file
add_service() {
  local service="$1"
  # Search subfolder first, then direct file
  if [ -f "composes/$service/docker-compose.yaml" ]; then
    FILES="$FILES -f composes/$service/docker-compose.yaml"
  elif [ -f "composes/$service/$service.docker-compose.yaml" ]; then
    FILES="$FILES -f composes/$service/$service.docker-compose.yaml"
  elif [ -f "composes/$service.docker-compose.yaml" ]; then
    FILES="$FILES -f composes/$service.docker-compose.yaml"
  fi
}

# Ingress Services
# Tunnel (enabled by default, can be disabled with ENABLE_TUNNEL=false)
if [ "${ENABLE_TUNNEL:-true}" = "true" ]; then
  add_service "tunnel"
fi

# Website (optional static site if present)
if [ -d "composes/website" ] || [ -f "composes/website.docker-compose.yaml" ]; then
  if [ "${ENABLE_WEBSITE:-true}" = "true" ]; then
    add_service "website"
  fi
fi

# Flag-based Services
# Format: FLAG_NAME|SERVICE_NAME
while read -r line; do
  if [ -z "$line" ]; then continue; fi
  FLAG="${line%%|*}"
  SERVICE="${line##*|}"
  
  # Check if flag is true (indirect expansion)
  VAL="${!FLAG:-false}"
  if [ "$VAL" = "true" ]; then
      add_service "$SERVICE"
  fi
done <<EOF
ENABLE_REVERSE_PROXY|traefik
ENABLE_DNS|dns
ENABLE_MONITORING|monitoring
ENABLE_LOGGING|logging
ENABLE_BACKUP|backup
ENABLE_HOME_AUTOMATION|home-assistant
ENABLE_VAULTWARDEN|vaultwarden
ENABLE_NEXTCLOUD|nextcloud
ENABLE_PORTAINER|portainer
ENABLE_NTFY|ntfy
ENABLE_GATUS|gatus
ENABLE_UPTIME_KUMA|gatus
ENABLE_WATCHTOWER|watchtower
ENABLE_IMMICH|immich
ENABLE_SEARXNG|searxng
ENABLE_MINECRAFT|minecraft
EOF

# Custom Files (both root composes/ and subdirectories)
for custom in composes/*.custom.docker-compose.yaml composes/*/*.custom.docker-compose.yaml; do
  if [ -e "$custom" ]; then
    FILES="$FILES -f $custom"
  fi
done

echo "$FILES"
