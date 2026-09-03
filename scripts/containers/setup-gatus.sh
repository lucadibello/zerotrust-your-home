#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Check enable flag (support ENABLE_GATUS, with fallback to legacy ENABLE_UPTIME_KUMA)
IS_ENABLED="${ENABLE_GATUS:-${ENABLE_UPTIME_KUMA:-false}}"
if [ "$IS_ENABLED" != "true" ]; then
  echo "[*] Gatus health monitoring is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
GATUS_DIR="$PROJECT_ROOT/composes/gatus"
mkdir -p "$GATUS_DIR/config"

# Create external networks if not already present
docker network create traefik-network >/dev/null 2>&1 || true
docker network create prometheus-network >/dev/null 2>&1 || true
docker network create loki-network >/dev/null 2>&1 || true
docker network create dns-network >/dev/null 2>&1 || true
docker network create home-network >/dev/null 2>&1 || true
docker network create immich-network >/dev/null 2>&1 || true
docker network create nextcloud-aio >/dev/null 2>&1 || true

# Render Gatus config from template
TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/gatus.yaml.template"
TARGET="$GATUS_DIR/config/config.yaml"

# If TARGET was accidentally created as a directory by Docker, remove it
if [ -d "$TARGET" ]; then
  rm -rf "$TARGET"
fi

render_template "$TEMPLATE" "$TARGET" \
  NTFY_URL="${NTFY_URL:-https://ntfy.home.lucadibello.ch}" \
  NTFY_TOPIC="${NTFY_TOPIC:-lucadibello-homelab-status}" \
  NTFY_TOKEN="${NTFY_TOKEN:-}" \
  DNS_DOMAIN="${DNS_DOMAIN:-example.com}"

# Dynamically build endpoints block
endpoints_block=""
count=0

# Helper function to process and append a gatus fragment
append_gatus_fragment() {
  local fragment_file="$1"
  local label="$2"

  if [ -f "$fragment_file" ]; then
    local temp_fragment
    temp_fragment="$(mktemp)"
    render_template "$fragment_file" "$temp_fragment" \
      DNS_DOMAIN="${DNS_DOMAIN:-example.com}" \
      NTFY_URL="${NTFY_URL:-https://ntfy.home.lucadibello.ch}" \
      NTFY_TOPIC="${NTFY_TOPIC:-lucadibello-homelab-status}" \
      NTFY_TOKEN="${NTFY_TOKEN:-}"

    local rendered_content
    rendered_content="$(cat "$temp_fragment")"
    rm -f "$temp_fragment"

    if [ -n "$rendered_content" ]; then
      # Indent fragment content to match endpoints block format (2 spaces)
      local indented_content
      indented_content="$(echo "$rendered_content" | sed 's/^/  /')"
      endpoints_block+=$'\n'"  # ${label}"$'\n'"${indented_content}"
      local fragment_count
      fragment_count=$(echo "$rendered_content" | grep -c '^\- name:' || true)
      count=$((count + fragment_count))
      echo "[*] Added Gatus endpoints from ${label} (${fragment_count} endpoint(s))"
    fi
  fi
}

# 1. Discover endpoints from core services (composes/<service>/gatus.yaml)
for service_dir in "$PROJECT_ROOT/composes"/*/; do
  if [ -d "$service_dir" ]; then
    service_name=$(basename "$service_dir")
    # Skip extras and gatus itself
    if [ "$service_name" = "extras" ] || [ "$service_name" = "gatus" ]; then
      continue
    fi

    if is_service_enabled "$service_name" false; then
      fragment=""
      if [ -f "${service_dir}gatus.yaml" ]; then
        fragment="${service_dir}gatus.yaml"
      elif [ -f "${service_dir}gatus.yml" ]; then
        fragment="${service_dir}gatus.yml"
      fi

      if [ -n "$fragment" ]; then
        append_gatus_fragment "$fragment" "Service: ${service_name}"
      fi
    fi
  fi
done

# 2. Discover endpoints from extra services (composes/extras/<service>/gatus.yaml)
EXTRAS_DIR="$PROJECT_ROOT/composes/extras"
if [ -d "$EXTRAS_DIR" ]; then
  for extra_dir in "$EXTRAS_DIR"/*/; do
    if [ -d "$extra_dir" ]; then
      service_name=$(basename "$extra_dir")
      fragment=""
      if [ -f "${extra_dir}gatus.yaml" ]; then
        fragment="${extra_dir}gatus.yaml"
      elif [ -f "${extra_dir}gatus.yml" ]; then
        fragment="${extra_dir}gatus.yml"
      fi

      if [ -n "$fragment" ]; then
        append_gatus_fragment "$fragment" "Extra: ${service_name}"
      fi
    fi
  done
fi

# Write endpoints to target configuration
if [ -n "$endpoints_block" ]; then
  {
    echo ""
    echo "endpoints:"
    printf "%s\n" "$endpoints_block"
  } >> "$TARGET"
else
  {
    echo ""
    echo "endpoints: []"
  } >> "$TARGET"
fi

echo "[OK] Gatus health monitoring setup completed ($count endpoints configured)"
