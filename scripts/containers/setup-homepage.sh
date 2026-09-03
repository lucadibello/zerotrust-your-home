#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Check enable flag
if [ "${ENABLE_HOMEPAGE:-false}" != "true" ]; then
  echo "[*] Homepage dashboard is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
HOMEPAGE_DIR="$PROJECT_ROOT/composes/homepage"
CONFIG_DIR="$HOMEPAGE_DIR/config"
mkdir -p "$CONFIG_DIR"

# Ensure external network exists
docker network create traefik-network >/dev/null 2>&1 || true

DOMAIN="${DNS_DOMAIN:-example.com}"

# 1. Generate settings.yaml
cat <<'EOF' > "$CONFIG_DIR/settings.yaml"
---
title: "ZeroTrust Home"
theme: dark
color: slate
headerStyle: clean
showStats: true
layout:
  Core Infrastructure:
    style: row
    columns: 4
  Monitoring:
    style: row
    columns: 3
  Security:
    style: row
    columns: 3
  Home Automation:
    style: row
    columns: 2
  Applications:
    style: row
    columns: 3
  Management:
    style: row
    columns: 3
EOF

# 2. Generate widgets.yaml
cat <<'EOF' > "$CONFIG_DIR/widgets.yaml"
---
- resources:
    cpu: true
    memory: true
    disk: /

- search:
    provider: duckduckgo
    target: _blank
EOF

# 3. Generate bookmarks.yaml
cat <<'EOF' > "$CONFIG_DIR/bookmarks.yaml"
---
- Links:
    - GitHub:
        - icon: github.png
          href: "https://github.com"
    - Cloudflare:
        - icon: cloudflare.png
          href: "https://dash.cloudflare.com"
EOF

# 4. Generate docker.yaml
cat <<'EOF' > "$CONFIG_DIR/docker.yaml"
---
my-docker:
  socket: /var/run/docker.sock
EOF

# 5. Dynamically build services.yaml based on enabled feature flags
services_file="$CONFIG_DIR/services.yaml"
rm -f "$services_file"

has_any_service=false

# --- Core Infrastructure ---
core_entries=""
if [ "${ENABLE_REVERSE_PROXY:-true}" = "true" ]; then
  core_entries+="    - Traefik:
        icon: traefik.png
        href: https://traefik.${DOMAIN}
        description: Reverse Proxy and Edge Router
"
fi

if [ "${ENABLE_GATUS:-${ENABLE_UPTIME_KUMA:-false}}" = "true" ]; then
  core_entries+="    - Status:
        icon: gatus.png
        href: https://status.${DOMAIN}
        description: Health and Uptime Monitoring
"
fi

if [ "${ENABLE_NTFY:-false}" = "true" ]; then
  core_entries+="    - Ntfy:
        icon: ntfy.png
        href: https://ntfy.${DOMAIN}
        description: Push Notifications Server
"
fi

if [ "${ENABLE_ADGUARD:-false}" = "true" ]; then
  core_entries+="    - AdGuard Home:
        icon: adguard-home.png
        href: https://adguard.${DOMAIN}
        description: DNS & DoH Ad-blocking
        server: my-docker
        container: adguard
"
fi

if [ -n "$core_entries" ]; then
  has_any_service=true
  cat <<EOF >> "$services_file"
- Core Infrastructure:
${core_entries}
EOF
fi

# --- Monitoring ---
monitoring_entries=""
if [ "${ENABLE_MONITORING:-true}" = "true" ]; then
  monitoring_entries+="    - Prometheus:
        icon: prometheus.png
        href: https://prometheus.${DOMAIN}
        description: Metrics and Time Series DB
    - Alertmanager:
        icon: alertmanager.png
        href: https://alerts.${DOMAIN}
        description: Alert Routing and Notification
    - Grafana:
        icon: grafana.png
        href: https://grafana.${DOMAIN}
        description: Dashboards and Analytics
"
fi

if [ -n "$monitoring_entries" ]; then
  has_any_service=true
  cat <<EOF >> "$services_file"
- Monitoring:
${monitoring_entries}
EOF
fi

# --- Security ---
security_entries=""
if [ "${ENABLE_VAULTWARDEN:-false}" = "true" ]; then
  security_entries+="    - Vaultwarden:
        icon: vaultwarden.png
        href: https://vault.${DOMAIN}
        description: Password and Secrets Manager
"
fi

if [ "${ENABLE_CROWDSEC:-false}" = "true" ]; then
  security_entries+="    - CrowdSec:
        icon: crowdsec.png
        description: Intrusion Prevention & Security Engine
        server: my-docker
        container: crowdsec
"
fi

if [ -n "$security_entries" ]; then
  has_any_service=true
  cat <<EOF >> "$services_file"
- Security:
${security_entries}
EOF
fi

# --- Home Automation ---
home_entries=""
if [ "${ENABLE_HOME_AUTOMATION:-false}" = "true" ]; then
  home_entries+="    - Home Assistant:
        icon: home-assistant.png
        href: https://home.${DOMAIN}
        description: Smart Home Automation
    - Zigbee2MQTT:
        icon: zigbee2mqtt.png
        href: https://zigbee2mqtt.${DOMAIN}
        description: Zigbee Device Bridge
"
fi

if [ -n "$home_entries" ]; then
  has_any_service=true
  cat <<EOF >> "$services_file"
- Home Automation:
${home_entries}
EOF
fi

# --- Applications ---
app_entries=""
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
  app_entries+="    - Immich:
        icon: immich.png
        href: https://photos.${DOMAIN}
        description: Photo and Video Management
"
fi

if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
  app_entries+="    - Nextcloud:
        icon: nextcloud.png
        href: https://cloud.${DOMAIN}
        description: Self-hosted Cloud Storage
"
fi

if [ "${ENABLE_SEARXNG:-false}" = "true" ]; then
  app_entries+="    - SearXNG:
        icon: searxng.png
        href: https://search.${DOMAIN}
        description: Privacy Metasearch Engine
"
fi

if [ -n "$app_entries" ]; then
  has_any_service=true
  cat <<EOF >> "$services_file"
- Applications:
${app_entries}
EOF
fi

# --- Management ---
mgmt_entries=""
if [ "${ENABLE_PORTAINER:-false}" = "true" ]; then
  mgmt_entries+="    - Portainer:
        icon: portainer.png
        href: https://docker.${DOMAIN}
        description: Docker Container Management
"
fi

if [ -n "$mgmt_entries" ]; then
  has_any_service=true
  cat <<EOF >> "$services_file"
- Management:
${mgmt_entries}
EOF
fi

if [ "$has_any_service" = false ]; then
  echo "[]" > "$services_file"
fi

echo "[OK] Homepage dashboard setup completed"
