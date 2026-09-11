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
         "$MEDIA_CONFIG_DIR/jellyseerr" \
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

# Hardware transcoding check
RENDER_DEV="${JELLYFIN_RENDER_DEVICE:-/dev/dri/renderD128}"
if [ "$RENDER_DEV" != "/dev/null" ] && [ ! -e "$RENDER_DEV" ]; then
  log_warn "Jellyfin GPU device '${RENDER_DEV}' was not found on host."
  log_warn "If this machine does not have an Intel/AMD GPU or PCIe passthrough, set JELLYFIN_RENDER_DEVICE=/dev/null in .env."
fi

echo "[OK] Media stack setup completed"
