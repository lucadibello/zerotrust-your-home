#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

FILES=""

# Helper function to add file
add_file() {
  if [ -f "composes/$1" ]; then
    FILES="$FILES -f composes/$1"
  fi
}

# Core Services (Always enabled or specific logic)
# Tunnel is core and required
add_file "tunnel.docker-compose.yaml"

# Website (No flag, assume enabled if present)
add_file "website.docker-compose.yaml"

# Flag-based Services
# Format: FLAG_NAME|FILENAME
# We use echo to feed the loop to avoid bash array compatibility issues if any (though bash 4+ is standard)
while read -r line; do
  if [ -z "$line" ]; then continue; fi
  FLAG="${line%%|*}"
  FILE="${line##*|}"
  
  # Check if flag is true
  # We use indirect expansion ${!FLAG}
  VAL="${!FLAG}"
  if [ "$VAL" = "true" ]; then
      add_file "$FILE"
  fi
done <<EOF
ENABLE_REVERSE_PROXY|traefik.docker-compose.yaml
ENABLE_DNS|dns.docker-compose.yaml
ENABLE_MONITORING|prometheus.docker-compose.yaml
ENABLE_LOGGING|loki.docker-compose.yaml
ENABLE_BACKUP|restic.docker-compose.yaml
ENABLE_HOME_AUTOMATION|home.docker-compose.yaml
ENABLE_VAULTWARDEN|vaultwarden.docker-compose.yaml
ENABLE_NEXTCLOUD|nextcloud.docker-compose.yaml
ENABLE_PORTAINER|portainer.docker-compose.yaml
ENABLE_UPTIME_KUMA|uptimekuma.docker-compose.yaml
ENABLE_WATCHTOWER|watchtower.docker-compose.yaml
ENABLE_IMMICH|immich.docker-compose.yaml
ENABLE_SEARXNG|searxng.docker-compose.yaml
ENABLE_MINECRAFT|mcserver.docker-compose.yaml
EOF

# Custom Files
# Find all files ending in .custom.docker-compose.yaml in composes/
# We use a loop to handle the glob expansion
for custom in composes/*.custom.docker-compose.yaml; do
  if [ -e "$custom" ]; then
    FILES="$FILES -f $custom"
  fi
done

echo "$FILES"
