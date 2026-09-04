#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

DYNAMIC_CONFIG_DIR="$PROJECT_ROOT/composes/traefik/dynamic"
CROWDSEC_BOUNCER_DIR="$PROJECT_ROOT/composes/traefik/crowdsec"
CROWDSEC_BOUNCER_FILE="$CROWDSEC_BOUNCER_DIR/BOUNCER_KEY_traefik"
TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/crowdsec.yml.template"
TARGET="$DYNAMIC_CONFIG_DIR/crowdsec.yml"

mkdir -p "$DYNAMIC_CONFIG_DIR" "$CROWDSEC_BOUNCER_DIR"

# If CrowdSec is disabled, configure Traefik bouncer plugin in bypass mode
if [ "${ENABLE_CROWDSEC:-false}" != "true" ]; then
  echo "[*] CrowdSec is disabled, configuring Traefik bouncer in bypass mode..."
  if [ ! -f "$CROWDSEC_BOUNCER_FILE" ]; then
    touch "$CROWDSEC_BOUNCER_FILE"
  fi
  render_template "$TEMPLATE" "$TARGET" \
    BOUNCER_ENABLED="false" \
    APPSEC_ENABLED="false" \
    APPSEC_FAILURE_BLOCK="false" \
    APPSEC_UNREACHABLE_BLOCK="false"
  exit 0
fi

# Ensure directories exist
mkdir -p "$PROJECT_ROOT/composes/crowdsec/data" \
  "$PROJECT_ROOT/composes/crowdsec/config" \
  "$PROJECT_ROOT/composes/traefik/logs"

# Ensure access.log file exists so docker doesn't mount it as a directory
touch "$PROJECT_ROOT/composes/traefik/logs/access.log"

# Ensure CrowdSec Prometheus metrics configuration exists
if [ ! -f "$PROJECT_ROOT/composes/crowdsec/config/config.yaml.local" ]; then
  cat << 'EOF' > "$PROJECT_ROOT/composes/crowdsec/config/config.yaml.local"
prometheus:
  enabled: true
  level: full
  listen_addr: 0.0.0.0
  listen_port: 6060
EOF
fi

# Create host log files if writable and missing
if [ -w "/var/log" ] 2>/dev/null; then
  [ ! -e "/var/log/auth.log" ] && touch /var/log/auth.log 2>/dev/null || true
  [ ! -e "/var/log/syslog" ] && touch /var/log/syslog 2>/dev/null || true
fi

# Ensure bouncer key is configured
BOUNCER_KEY="${CROWDSEC_BOUNCER_KEY:-}"
if [ -z "$BOUNCER_KEY" ]; then
  if [ -f "$CROWDSEC_BOUNCER_FILE" ] && [ -s "$CROWDSEC_BOUNCER_FILE" ]; then
    BOUNCER_KEY=$(tr -d '[:space:]' < "$CROWDSEC_BOUNCER_FILE")
  else
    echo "[*] Generating secure random CrowdSec bouncer key..."
    BOUNCER_KEY=$(openssl rand -hex 32)
  fi

  # Persist to .env
  if [ -f "$PROJECT_ROOT/.env" ]; then
    if grep -q "^CROWDSEC_BOUNCER_KEY=" "$PROJECT_ROOT/.env"; then
      $SED_INPLACE "s|^CROWDSEC_BOUNCER_KEY=.*|CROWDSEC_BOUNCER_KEY=$BOUNCER_KEY|" "$PROJECT_ROOT/.env"
    else
      echo "" >> "$PROJECT_ROOT/.env"
      echo "## CrowdSec bouncer API key (auto-generated)" >> "$PROJECT_ROOT/.env"
      echo "CROWDSEC_BOUNCER_KEY=$BOUNCER_KEY" >> "$PROJECT_ROOT/.env"
    fi
  fi
fi

# Write bouncer key file for Traefik mount
printf "%s" "$BOUNCER_KEY" > "$CROWDSEC_BOUNCER_FILE"
chmod 644 "$CROWDSEC_BOUNCER_FILE"

# Render dynamic configuration for Traefik bouncer plugin
render_template "$TEMPLATE" "$TARGET" \
  BOUNCER_ENABLED="true" \
  APPSEC_ENABLED="true" \
  APPSEC_FAILURE_BLOCK="true" \
  APPSEC_UNREACHABLE_BLOCK="true"

# Create external network if needed
docker network create traefik-network >/dev/null 2>&1 || true

echo "[OK] CrowdSec setup completed"

