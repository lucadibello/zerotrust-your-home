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
  echo "[*] Monitoring is disabled, skipping Alertmanager setup..."
  exit 0
fi

ALERTMANAGER_DIR="$PROJECT_ROOT/composes/monitoring/alertmanager"
mkdir -p "$ALERTMANAGER_DIR"

TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/alertmanager.yml.template"
TARGET="$ALERTMANAGER_DIR/alertmanager.yml"

# If TARGET was accidentally created as a directory by Docker, remove it
if [ -d "$TARGET" ]; then
  rm -rf "$TARGET"
fi

# Safely render the Alertmanager configuration with ntfy endpoint
render_template "$TEMPLATE" "$TARGET" \
  NTFY_URL="${NTFY_URL:-https://ntfy.sh}" \
  NTFY_TOPIC="${NTFY_TOPIC:-zerotrust-alerts}"

echo "[OK] AlertManager setup completed"
