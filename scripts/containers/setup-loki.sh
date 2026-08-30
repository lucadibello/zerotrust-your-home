#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Skip if Logging is disabled
if [ "${ENABLE_LOGGING:-true}" != "true" ]; then
  echo "[*] Logging is disabled, skipping Loki setup..."
  exit 0
fi

# Ensure directories exist
mkdir -p "$PROJECT_ROOT/composes/logging/loki" \
         "$PROJECT_ROOT/composes/logging/promtail"

# Create networks for Loki log ingestion and Grafana/Alertmanager communication
sudo docker network create loki-network >/dev/null 2>&1 || true
sudo docker network create prometheus-network >/dev/null 2>&1 || true

echo "[OK] Loki logging setup completed"
