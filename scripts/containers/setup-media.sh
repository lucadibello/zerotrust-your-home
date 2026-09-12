#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if Media stack is not enabled
if ! is_service_enabled "media" false; then
  echo "[*] Media stack is disabled, skipping setup..."
  exit 0
fi

MEDIA_DIR="${MEDIA_DIR:-/mnt/media}"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-/mnt/downloads}"
MEDIA_CONFIG_DIR="$PROJECT_ROOT/composes/media/config"
MEDIA_CACHE_DIR="$PROJECT_ROOT/composes/media/cache"

echo "[*] Setting up Media stack directories..."

# Create container configuration & cache directories
mkdir -p "$MEDIA_CONFIG_DIR/jellyfin" \
  "$MEDIA_CONFIG_DIR/seerr" \
  "$MEDIA_CONFIG_DIR/radarr" \
  "$MEDIA_CONFIG_DIR/sonarr" \
  "$MEDIA_CONFIG_DIR/prowlarr" \
  "$MEDIA_CONFIG_DIR/qbittorrent" \
  "$MEDIA_CONFIG_DIR/bazarr" \
  "$MEDIA_CACHE_DIR/jellyfin"

# Attempt to create host media & downloads folders if writable
mkdir -p "$MEDIA_DIR/movies" \
  "$MEDIA_DIR/tv" \
  "$DOWNLOADS_DIR" 2>/dev/null || true

# Ensure external networks exist
ensure_network "traefik-network"
ensure_network "media-network"

# Configure qBittorrent for Traefik reverse proxy (disable Host header validation)
QBT_CONF_DIR="$MEDIA_CONFIG_DIR/qbittorrent/qBittorrent"
QBT_CONF="$QBT_CONF_DIR/qBittorrent.conf"
mkdir -p "$QBT_CONF_DIR"
if [ ! -f "$QBT_CONF" ]; then
  cat <<'EOF' >"$QBT_CONF"
[Preferences]
WebUI\HostHeaderValidation=false
EOF
elif ! grep -q "HostHeaderValidation" "$QBT_CONF"; then
  if grep -q "\[Preferences\]" "$QBT_CONF"; then
    $SED_INPLACE '/\[Preferences\]/a WebUI\\HostHeaderValidation=false' "$QBT_CONF"
  else
    printf "\n[Preferences]\nWebUI\\HostHeaderValidation=false\n" >>"$QBT_CONF"
  fi
fi

# Hardware transcoding check
RENDER_DEV="${JELLYFIN_RENDER_DEVICE:-/dev/null}"
if [ "$RENDER_DEV" != "/dev/null" ] && [ ! -e "$RENDER_DEV" ]; then
  log_warn "Jellyfin GPU device '${RENDER_DEV}' was not found on host."

  VIRT_TYPE="none"
  if command -v detect_virtualization >/dev/null 2>&1; then
    VIRT_TYPE=$(detect_virtualization)
  fi

  if [ "$VIRT_TYPE" = "kvm" ] || [ "$VIRT_TYPE" = "qemu" ]; then
    log_info "Detected ${VIRT_TYPE} virtual machine without a passed-through GPU."
  fi

  if [ -f "$PROJECT_ROOT/.env" ] && grep -q "^JELLYFIN_RENDER_DEVICE=" "$PROJECT_ROOT/.env"; then
    log_info "Auto-adjusting JELLYFIN_RENDER_DEVICE=/dev/null in .env to prevent container startup failure."
    $SED_INPLACE 's|^JELLYFIN_RENDER_DEVICE=.*|JELLYFIN_RENDER_DEVICE=/dev/null|' "$PROJECT_ROOT/.env"
  fi
  log_info "Jellyfin will use CPU software transcoding."
fi

echo "[OK] Media stack setup completed"
