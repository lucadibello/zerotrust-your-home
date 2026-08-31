#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if Monitoring is disabled
if [ "${ENABLE_MONITORING:-true}" != "true" ]; then
  echo "[*] Monitoring is disabled, skipping Prometheus setup..."
  exit 0
fi

# Ensure monitoring directory structure exists
mkdir -p "$PROJECT_ROOT/composes/monitoring/prometheus" \
         "$PROJECT_ROOT/composes/monitoring/alertmanager" \
         "$PROJECT_ROOT/composes/monitoring/grafana/dashboards" \
         "$PROJECT_ROOT/composes/monitoring/grafana/settings/dashboards" \
         "$PROJECT_ROOT/composes/monitoring/grafana/settings/datasources"

# Create external prometheus network
docker network create prometheus-network >/dev/null 2>&1 || true

echo "[OK] Prometheus monitoring setup completed"
