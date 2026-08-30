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

# Clean and validate TELEGRAM_CHAT_ID (Alertmanager requires int64 for chat_id)
CLEAN_CHAT_ID=$(echo "${TELEGRAM_CHAT_ID:-0}" | tr -d '"'\'' ')
if [[ ! "$CLEAN_CHAT_ID" =~ ^-?[0-9]+$ ]] || [ -z "$CLEAN_CHAT_ID" ]; then
  echo "[!] Warning: TELEGRAM_CHAT_ID ('${TELEGRAM_CHAT_ID:-}') is not a valid numeric Telegram Chat ID."
  echo "[!] Using placeholder '0' in alertmanager.yml to prevent Alertmanager YAML parsing crash."
  CLEAN_CHAT_ID="0"
fi

TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/alertmanager.yml.template"
TARGET="$PROJECT_ROOT/composes/monitoring/alertmanager/alertmanager.yml"

# Safely render the Alertmanager configuration
render_template "$TEMPLATE" "$TARGET" \
  BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-placeholder}" \
  CHAT_ID="$CLEAN_CHAT_ID"

echo "[OK] AlertManager setup completed"
