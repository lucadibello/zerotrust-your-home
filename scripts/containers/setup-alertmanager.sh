#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Skip if Monitoring is disabled
if [ "${ENABLE_MONITORING:-true}" != "true" ]; then
  echo "[*] Monitoring is disabled, skipping Alertmanager setup..."
  exit 0
fi

TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/alertmanager.yml.template"
TARGET="$PROJECT_ROOT/composes/monitoring/alertmanager/alertmanager.yml"

# Safely render the Alertmanager configuration with ntfy endpoint
render_template "$TEMPLATE" "$TARGET" \
  NTFY_URL="${NTFY_URL:-https://ntfy.sh}" \
  NTFY_TOPIC="${NTFY_TOPIC:-zerotrust-alerts}"

echo "[OK] AlertManager setup completed"
