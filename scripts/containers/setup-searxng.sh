#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if SearXNG is not enabled
if [ "${ENABLE_SEARXNG:-false}" != "true" ]; then
  echo "[*] SearXNG is disabled, skipping setup..."
  exit 0
fi

SEARXNG_DIR="$PROJECT_ROOT/composes/searxng"
mkdir -p "$SEARXNG_DIR"

TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/settings.yml.template"
TARGET="$SEARXNG_DIR/settings.yml"

# If TARGET was accidentally created as a directory by Docker, remove it
if [ -d "$TARGET" ]; then
  rm -rf "$TARGET"
fi

# Safely render the SearXNG configuration
render_template "$TEMPLATE" "$TARGET" \
  SEARCHXNG_SECRET_KEY="$SEARCHXNG_SECRET_KEY"

echo "[OK] SearXNG setup completed"
