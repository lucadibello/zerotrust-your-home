#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if CrowdSec is not enabled
if [ "${ENABLE_CROWDSEC:-false}" != "true" ]; then
  echo "[*] CrowdSec is disabled, skipping setup..."
  exit 0
fi

# Ensure directories exist
mkdir -p "$PROJECT_ROOT/composes/crowdsec/data" \
  "$PROJECT_ROOT/composes/crowdsec/config" \
  "$PROJECT_ROOT/composes/traefik/logs"

# Ensure access.log file exists so docker doesn't mount it as a directory
touch "$PROJECT_ROOT/composes/traefik/logs/access.log"

# create files if missing
if [ -w "/var/log" ] 2>/dev/null; then
  [ ! -e "/var/log/auth.log" ] && touch /var/log/auth.log 2>/dev/null || true
  [ ! -e "/var/log/syslog" ] && touch /var/log/syslog 2>/dev/null || true
fi

# Create external network if needed
docker network create traefik-network >/dev/null 2>&1 || true

echo "[OK] CrowdSec setup completed"
