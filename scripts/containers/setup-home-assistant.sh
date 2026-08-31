#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if Home Automation is not enabled
if [ "${ENABLE_HOME_AUTOMATION:-false}" != "true" ]; then
  echo "[*] Home Automation is disabled, skipping setup..."
  exit 0
fi

HA_DIR="$PROJECT_ROOT/composes/home-assistant"

# Ensure directories exist
mkdir -p "$HA_DIR/certs" \
         "$HA_DIR/mosquitto/certs" \
         "$HA_DIR/mosquitto/log" \
         "$HA_DIR/zigbee2mqtt/certs"

# Create external home-network for isolated IoT communication
docker network create home-network >/dev/null 2>&1 || true

# Generate TLS certificates for Home Automation if not present
if [ ! -f "$HA_DIR/mosquitto/certs/ca.crt" ] && [ -f "$PROJECT_ROOT/scripts/certs/generate-certificates.sh" ]; then
  echo "[*] Generating certificates for Home Automation..."
  bash "$PROJECT_ROOT/scripts/certs/generate-certificates.sh"
fi

# Initialize mosquitto.conf if not present
if [ ! -f "$HA_DIR/mosquitto/mosquitto.conf" ]; then
  echo "[*] Creating default mosquitto.conf..."
  cat <<'EOF' > "$HA_DIR/mosquitto/mosquitto.conf"
listener 1883
allow_anonymous true

listener 8883
cafile /mosquitto/certs/ca.crt
certfile /mosquitto/certs/service.crt
keyfile /mosquitto/certs/service.key
require_certificate false

persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOF
fi

# Initialize Home Assistant configuration.yaml if not present
if [ ! -f "$HA_DIR/configuration.yaml" ]; then
  echo "[*] Creating default Home Assistant configuration.yaml..."
  cat <<'EOF' > "$HA_DIR/configuration.yaml"
# Loads default set of integrations. Do not remove.
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
    - 10.0.0.0/8
    - 192.168.0.0/16
EOF
fi

# Initialize automations.yaml if not present
if [ ! -f "$HA_DIR/automations.yaml" ]; then
  touch "$HA_DIR/automations.yaml"
fi

echo "[OK] Home Automation setup completed"
