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

# Skip if Monitoring is disabled
if [ "${ENABLE_MONITORING:-true}" != "true" ]; then
  echo "[*] Monitoring is disabled, skipping Prometheus setup..."
  exit 0
fi

# Ensure monitoring directory structure exists
mkdir -p "$PROJECT_ROOT/composes/monitoring/prometheus" \
         "$PROJECT_ROOT/composes/monitoring/alertmanager" \
         "$PROJECT_ROOT/composes/monitoring/grafana"

# Create external prometheus network
sudo docker network create prometheus-network >/dev/null 2>&1 || true

echo "[OK] Prometheus monitoring setup completed"
