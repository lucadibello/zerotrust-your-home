#!/bin/bash
trap "exit" INT

# Load environment variables
set -a
source .env
set +a

# Skip if Uptime Kuma is not enabled
if [ "$ENABLE_UPTIME_KUMA" != "true" ]; then
  echo "[*] Uptime Kuma is disabled, skipping setup..."
  exit 0
fi

# Create required directories (ignore if already exists)
mkdir -p ./composes/uptime-kuma || true

# Copy sqlite database to composes directory
cp ./scripts/containers/templates/kuma.db.template ./composes/uptime-kuma/kuma.db

# Create a new user
sqlite3 ./composes/uptime-kuma/kuma.db "INSERT INTO notification (id, name, config, active, user_id, is_default) VALUES (1, 'Telegram Alert Bot', '{\"name\":\"Telegram Alert Bot\",\"type\":\"telegram\",\"isDefault\":true,\"telegramBotToken\":\"$TELEGRAM_BOT_TOKEN\",\"telegramChatID\":\"$TELEGRAM_CHAT_ID\",\"applyExisting\":true}', 1, 1, 1);"

echo "[OK] Uptime Kuma setup completed"
