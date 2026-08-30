#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Skip if SearXNG is not enabled
if [ "${ENABLE_SEARXNG:-false}" != "true" ]; then
  echo "[*] SearXNG is disabled, skipping setup..."
  exit 0
fi

TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/settings.yml.template"
TARGET="$PROJECT_ROOT/composes/searxng/settings.yml"

# Safely render the SearXNG configuration
render_template "$TEMPLATE" "$TARGET" \
  SEARCHXNG_SECRET_KEY="$SEARCHXNG_SECRET_KEY"

echo "[OK] SearXNG setup completed"
