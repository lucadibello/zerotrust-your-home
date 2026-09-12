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
ENV_FILE="$PROJECT_ROOT/.env"

# Auto-generate missing media secrets in .env
generate_secret_if_missing() {
  local var_name="$1"
  local val="${!var_name:-}"
  if [ -z "$val" ]; then
    local new_val
    if [[ "$var_name" == *"KEY"* ]]; then
      new_val=$(openssl rand -hex 16)
    else
      new_val=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    fi
    export "$var_name"="$new_val"
    if [ -f "$ENV_FILE" ]; then
      if grep -q "^${var_name}=" "$ENV_FILE"; then
        $SED_INPLACE "s|^${var_name}=.*|${var_name}=${new_val}|" "$ENV_FILE"
      else
        echo "${var_name}=${new_val}" >> "$ENV_FILE"
      fi
    fi
  fi
}

generate_secret_if_missing "RADARR_API_KEY"
generate_secret_if_missing "SONARR_API_KEY"
generate_secret_if_missing "PROWLARR_API_KEY"
generate_secret_if_missing "BAZARR_API_KEY"
generate_secret_if_missing "JELLYFIN_ADMIN_PASSWORD"
generate_secret_if_missing "QBITTORRENT_WEBUI_PASSWORD"

export JELLYFIN_ADMIN_USER="${JELLYFIN_ADMIN_USER:-admin}"
export QBITTORRENT_WEBUI_USERNAME="${QBITTORRENT_WEBUI_USERNAME:-admin}"

echo "[*] Setting up Media stack directories..."

# Create container configuration & cache directories
mkdir -p "$MEDIA_CONFIG_DIR/jellyfin/config" \
  "$MEDIA_CONFIG_DIR/seerr" \
  "$MEDIA_CONFIG_DIR/radarr" \
  "$MEDIA_CONFIG_DIR/sonarr" \
  "$MEDIA_CONFIG_DIR/prowlarr" \
  "$MEDIA_CONFIG_DIR/qbittorrent/qBittorrent" \
  "$MEDIA_CONFIG_DIR/bazarr/config" \
  "$MEDIA_CACHE_DIR/jellyfin"

# Attempt to create host media & downloads folders if writable
mkdir -p "$MEDIA_DIR/movies" \
  "$MEDIA_DIR/tv" \
  "$DOWNLOADS_DIR" 2>/dev/null || true

# Ensure external networks exist
ensure_network "traefik-network"
ensure_network "media-network"

# Pre-configure qBittorrent preferences with strict password authentication
QBT_CONF="$MEDIA_CONFIG_DIR/qbittorrent/qBittorrent/qBittorrent.conf"
qbt_was_running=false
if command -v docker >/dev/null 2>&1; then
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^qbittorrent$'; then
    echo "[*] Stopping running qBittorrent container to prevent in-memory config overwrite..."
    docker stop qbittorrent >/dev/null 2>&1 || true
    qbt_was_running=true
  fi
fi

python3 "$PROJECT_ROOT/scripts/containers/configure-qbittorrent.py" \
  "$QBT_CONF" "$QBITTORRENT_WEBUI_USERNAME" "$QBITTORRENT_WEBUI_PASSWORD"

if [ "$qbt_was_running" = true ]; then
  echo "[*] Starting qBittorrent with updated credentials..."
  docker start qbittorrent >/dev/null 2>&1 || true
  echo "[OK] qBittorrent started successfully"
fi


QBT_CATEGORIES="$MEDIA_CONFIG_DIR/qbittorrent/qBittorrent/categories.json"
if [ ! -f "$QBT_CATEGORIES" ]; then
  cat <<'EOF' >"$QBT_CATEGORIES"
{
  "radarr": {
    "save_path": "/downloads/movies"
  },
  "sonarr": {
    "save_path": "/downloads/tv"
  }
}
EOF
fi

# Pre-configure Radarr config.xml
RADARR_CONF="$MEDIA_CONFIG_DIR/radarr/config.xml"
if [ ! -f "$RADARR_CONF" ]; then
  cat <<EOF >"$RADARR_CONF"
<Config>
  <LogLevel>info</LogLevel>
  <Port>7878</Port>
  <UrlBase></UrlBase>
  <BindAddress>*</BindAddress>
  <ApiKey>${RADARR_API_KEY}</ApiKey>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <Branch>master</Branch>
  <LaunchBrowser>False</LaunchBrowser>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>False</AnalyticsEnabled>
</Config>
EOF
else
  if grep -q "<ApiKey>" "$RADARR_CONF"; then
    $SED_INPLACE "s|<ApiKey>.*</ApiKey>|<ApiKey>${RADARR_API_KEY}</ApiKey>|" "$RADARR_CONF"
  fi
fi

# Pre-configure Sonarr config.xml
SONARR_CONF="$MEDIA_CONFIG_DIR/sonarr/config.xml"
if [ ! -f "$SONARR_CONF" ]; then
  cat <<EOF >"$SONARR_CONF"
<Config>
  <LogLevel>info</LogLevel>
  <Port>8989</Port>
  <UrlBase></UrlBase>
  <BindAddress>*</BindAddress>
  <ApiKey>${SONARR_API_KEY}</ApiKey>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <Branch>main</Branch>
  <LaunchBrowser>False</LaunchBrowser>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>False</AnalyticsEnabled>
</Config>
EOF
else
  if grep -q "<ApiKey>" "$SONARR_CONF"; then
    $SED_INPLACE "s|<ApiKey>.*</ApiKey>|<ApiKey>${SONARR_API_KEY}</ApiKey>|" "$SONARR_CONF"
  fi
fi

# Pre-configure Prowlarr config.xml
PROWLARR_CONF="$MEDIA_CONFIG_DIR/prowlarr/config.xml"
if [ ! -f "$PROWLARR_CONF" ]; then
  cat <<EOF >"$PROWLARR_CONF"
<Config>
  <LogLevel>info</LogLevel>
  <Port>9696</Port>
  <UrlBase></UrlBase>
  <BindAddress>*</BindAddress>
  <ApiKey>${PROWLARR_API_KEY}</ApiKey>
  <AuthenticationMethod>None</AuthenticationMethod>
  <AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>
  <Branch>master</Branch>
  <LaunchBrowser>False</LaunchBrowser>
  <UpdateMechanism>Docker</UpdateMechanism>
  <AnalyticsEnabled>False</AnalyticsEnabled>
</Config>
EOF
else
  if grep -q "<ApiKey>" "$PROWLARR_CONF"; then
    $SED_INPLACE "s|<ApiKey>.*</ApiKey>|<ApiKey>${PROWLARR_API_KEY}</ApiKey>|" "$PROWLARR_CONF"
  fi
fi

# Pre-configure Bazarr config.yaml
BAZARR_CONF="$MEDIA_CONFIG_DIR/bazarr/config/config.yaml"
if [ ! -f "$BAZARR_CONF" ]; then
  cat <<EOF >"$BAZARR_CONF"
general:
  use_radarr: true
  use_sonarr: true
  path_mappings_movie: []
  path_mappings_series: []
radarr:
  ip: "radarr"
  port: 7878
  apikey: "${RADARR_API_KEY}"
  base_url: "/"
  ssl: false
sonarr:
  ip: "sonarr"
  port: 8989
  apikey: "${SONARR_API_KEY}"
  base_url: "/"
  ssl: false
auth:
  type: "None"
  apikey: "${BAZARR_API_KEY}"
EOF
fi

# Pre-configure Jellyfin network configuration
LOCAL_NETWORK="${LOCAL_NETWORK:-192.168.0.0/24}"
JELLYFIN_NET_XML="$MEDIA_CONFIG_DIR/jellyfin/config/network.xml"
if [ ! -f "$JELLYFIN_NET_XML" ]; then
  cat <<EOF >"$JELLYFIN_NET_XML"
<?xml version="1.0" encoding="utf-8"?>
<NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <RequireHttps>false</RequireHttps>
  <EnableRemoteAccess>true</EnableRemoteAccess>
  <KnownProxies>
    <string>127.0.0.1</string>
    <string>10.0.0.0/8</string>
    <string>172.16.0.0/12</string>
    <string>${LOCAL_NETWORK}</string>
  </KnownProxies>
</NetworkConfiguration>
EOF
  cp "$JELLYFIN_NET_XML" "$MEDIA_CONFIG_DIR/jellyfin/network.xml" 2>/dev/null || true
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

