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

# Skip if Uptime Kuma is not enabled
if [ "${ENABLE_UPTIME_KUMA:-false}" != "true" ]; then
  echo "[*] Uptime Kuma is disabled, skipping setup..."
  exit 0
fi

# Ensure directories exist
KUMA_DIR="$PROJECT_ROOT/composes/uptimekuma"
mkdir -p "$KUMA_DIR"

# Create docker volume for Uptime Kuma data
sudo docker volume create uptimekuma_data >/dev/null 2>&1 || true

# Seed database template if kuma.db doesn't exist yet
if [ ! -f "$KUMA_DIR/kuma.db" ]; then
  cp "$PROJECT_ROOT/scripts/containers/templates/kuma.db.template" "$KUMA_DIR/kuma.db"
fi

# Safely update the notification settings in SQLite database
if command -v python3 >/dev/null 2>&1; then
  python3 - "$KUMA_DIR/kuma.db" "${TELEGRAM_BOT_TOKEN:-}" "${TELEGRAM_CHAT_ID:-}" <<'EOF'
import sys
import sqlite3
import json

db_path = sys.argv[1]
bot_token = sys.argv[2]
chat_id = sys.argv[3]

if bot_token and chat_id:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    config_json = json.dumps({
        "name": "Telegram Alert Bot",
        "type": "telegram",
        "isDefault": True,
        "telegramBotToken": bot_token,
        "telegramChatID": chat_id,
        "applyExisting": True
    })
    cursor.execute("DELETE FROM notification WHERE id = 1")
    cursor.execute(
        "INSERT INTO notification (id, name, config, active, user_id, is_default) VALUES (1, 'Telegram Alert Bot', ?, 1, 1, 1)",
        (config_json,)
    )
    conn.commit()
    conn.close()
EOF
elif command -v sqlite3 >/dev/null 2>&1; then
  safe_token=$(printf '%s' "${TELEGRAM_BOT_TOKEN:-}" | sed "s/'/''/g")
  safe_chat_id=$(printf '%s' "${TELEGRAM_CHAT_ID:-}" | sed "s/'/''/g")
  sqlite3 "$KUMA_DIR/kuma.db" "DELETE FROM notification WHERE id = 1; INSERT INTO notification (id, name, config, active, user_id, is_default) VALUES (1, 'Telegram Alert Bot', '{\"name\":\"Telegram Alert Bot\",\"type\":\"telegram\",\"isDefault\":true,\"telegramBotToken\":\"$safe_token\",\"telegramChatID\":\"$safe_chat_id\",\"applyExisting\":true}', 1, 1, 1);"
fi

echo "[OK] Uptime Kuma setup completed"
