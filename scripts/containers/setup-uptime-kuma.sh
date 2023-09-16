#!/bin/bash

# Create required directories (ignore if already exists)
mkdir -p ./composes/uptime-kuma || true

# Load environment variables
set -a
source .env
set +a

# Copy sqlite database to composes directory
cp ./scripts/containers/templates/kuma.db.template ./composes/uptime-kuma/kuma.db

# Create a new user
sqlite3 ./composes/uptime-kuma/kuma.db "INSERT INTO notification (id, name, config, active, user_id, is_default) VALUES (1, 'Telegram Alert Bot', '{\"name\":\"Telegram Alert Bot\",\"type\":\"telegram\",\"isDefault\":true,\"telegramBotToken\":\"$TELEGRAM_BOT_TOKEN\",\"telegramChatID\":\"$TELEGRAM_CHAT_ID\",\"applyExisting\":true}', 1, 1, 1);"