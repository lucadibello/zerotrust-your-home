#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if Logging is disabled
if [ "${ENABLE_LOGGING:-true}" != "true" ]; then
  echo "[*] Logging is disabled, skipping Loki setup..."
  exit 0
fi

# Ensure directories exist
mkdir -p "$PROJECT_ROOT/composes/logging/loki" \
         "$PROJECT_ROOT/composes/logging/promtail" \
         /var/log/audit /var/log/immich-go 2>/dev/null || true

# Create networks for Loki log ingestion and Grafana/Alertmanager communication
docker network create loki-network >/dev/null 2>&1 || true
docker network create prometheus-network >/dev/null 2>&1 || true

echo "[OK] Loki logging setup completed"
