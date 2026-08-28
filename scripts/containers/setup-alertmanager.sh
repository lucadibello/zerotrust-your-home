#!/bin/bash
trap "exit" INT

# Load common features
source ./scripts/common.sh

# Create required directories (ignore if already exists)
mkdir -p ./composes/alertmanager ./.tmp/alertmanager || true

# Load environment variables
set -a
source .env
set +a

# Clean and validate TELEGRAM_CHAT_ID (Alertmanager requires int64 for chat_id)
CLEAN_CHAT_ID=$(echo "${TELEGRAM_CHAT_ID:-0}" | tr -d '"'\'' ')
if [[ ! "$CLEAN_CHAT_ID" =~ ^-?[0-9]+$ ]] || [ -z "$CLEAN_CHAT_ID" ]; then
  echo "[!] Warning: TELEGRAM_CHAT_ID ('$TELEGRAM_CHAT_ID') is not a valid numeric Telegram Chat ID."
  echo "[!] Using placeholder '0' in alertmanager.yml to prevent Alertmanager YAML parsing crash."
  CLEAN_CHAT_ID="0"
fi

# Replace variables in configuration file
sed "s/<BOT_TOKEN>/${TELEGRAM_BOT_TOKEN:-placeholder}/g" ./scripts/containers/templates/alertmanager.yml.template | tee ./.tmp/alertmanager/alertmanager.yml >/dev/null
$SED_INPLACE "s/<CHAT_ID>/$CLEAN_CHAT_ID/g" ./.tmp/alertmanager/alertmanager.yml

# Move configuration file to composes directory
mv ./.tmp/alertmanager/alertmanager.yml ./composes/alertmanager/alertmanager.yml

# Remove temporary directory
rm -rf ./.tmp/alertmanager

echo "[OK] AlertManager setup completed"

