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
  NTFY_URL="${NTFY_URL:-https://ntfy.sh}" \
  NTFY_TOPIC="${NTFY_TOPIC:-zerotrust-alerts}" \
  NTFY_TOKEN="${NTFY_TOKEN:-}" \
  DNS_DOMAIN="${DNS_DOMAIN:-example.com}"

# Dynamically build endpoints block based on enabled feature flags
endpoints_block=""
count=0

# Core Infrastructure: Traefik (ENABLE_REVERSE_PROXY)
if [ "${ENABLE_REVERSE_PROXY:-true}" = "true" ]; then
  endpoints_block+='
  # Traefik Ingress
  - name: Traefik Ingress
    group: Core Infrastructure
    url: "http://traefik:80/ping"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
      - "[BODY] == OK"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Core Infrastructure: Ntfy (ENABLE_NTFY)
if [ "${ENABLE_NTFY:-false}" = "true" ]; then
  endpoints_block+='
  # Ntfy (Push Notifications)
  - name: Ntfy (Push Notifications)
    group: Core Infrastructure
    url: "http://ntfy:80/v1/health"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[BODY].healthy == true"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Dashboard: Homepage (ENABLE_HOMEPAGE)
if [ "${ENABLE_HOMEPAGE:-false}" = "true" ]; then
  endpoints_block+='
  # Homepage Dashboard
  - name: Homepage Dashboard
    group: Core Infrastructure
    url: "http://homepage:3000"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Core Infrastructure: BIND9 DNS (ENABLE_DNS)
if [ "${ENABLE_DNS:-true}" = "true" ]; then
  domain_name="${DNS_DOMAIN:-example.com}"
  endpoints_block+="
  # BIND9 DNS
  - name: BIND9 DNS
    group: Core Infrastructure
    url: \"bind9:53\"
    dns:
      query-name: \"${domain_name}\"
      query-type: \"A\"
    interval: 60s
    conditions:
      - \"[STATUS] == NOERROR\"
    alerts:
      - type: ntfy
        enabled: true
"
  count=$((count + 1))
fi

# Monitoring & Observability: Prometheus, Alertmanager, Grafana (ENABLE_MONITORING)
if [ "${ENABLE_MONITORING:-true}" = "true" ]; then
  endpoints_block+='
  # Monitoring: Prometheus
  - name: Prometheus
    group: Monitoring
    url: "http://prometheus:9090/-/ready"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
      - "[BODY] == pat(*Prometheus Server is Ready.*)"
    alerts:
      - type: ntfy
        enabled: true

  # Monitoring: Alertmanager
  - name: Alertmanager
    group: Monitoring
    url: "http://alertmanager:9093/-/ready"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
      - "[BODY] == OK"
    alerts:
      - type: ntfy
        enabled: true

  # Monitoring: Grafana
  - name: Grafana
    group: Monitoring
    url: "http://grafana:3000/api/health"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
      - "[BODY].database == ok"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 3))
fi

# Logging: Loki (ENABLE_LOGGING)
if [ "${ENABLE_LOGGING:-true}" = "true" ]; then
  endpoints_block+='
  # Logging: Loki
  - name: Loki
    group: Logging
    url: "http://loki:3100/ready"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
      - "[BODY] == ready"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Security: Vaultwarden (ENABLE_VAULTWARDEN)
if [ "${ENABLE_VAULTWARDEN:-false}" = "true" ]; then
  endpoints_block+='
  # Security: Vaultwarden
  - name: Vaultwarden
    group: Security
    url: "http://vaultwarden:80/alive"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Home Automation: Home Assistant & Zigbee2MQTT (ENABLE_HOME_AUTOMATION)
if [ "${ENABLE_HOME_AUTOMATION:-false}" = "true" ]; then
  endpoints_block+='
  # Home Automation: Home Assistant
  - name: Home Assistant
    group: Home Automation
    url: "http://homeassistant:8123/manifest.json"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[BODY].name == Home Assistant"
    alerts:
      - type: ntfy
        enabled: true

  # Home Automation: Zigbee2MQTT
  - name: Zigbee2MQTT
    group: Home Automation
    url: "http://zigbee2mqtt:8080"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[BODY] == pat(*Zigbee2MQTT*)"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 2))
fi

# Applications: Immich (ENABLE_IMMICH)
if [ "${ENABLE_IMMICH:-false}" = "true" ]; then
  endpoints_block+='
  # Applications: Immich
  - name: Immich
    group: Applications
    url: "http://immich_server:2283/api/server-info/ping"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[BODY].res == pong"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Applications: Nextcloud (ENABLE_NEXTCLOUD)
if [ "${ENABLE_NEXTCLOUD:-false}" = "true" ]; then
  endpoints_block+='
  # Applications: Nextcloud
  - name: Nextcloud
    group: Applications
    url: "http://nextcloud-aio-apache:11000/status.php"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[BODY].installed == true"
      - "[BODY].maintenance == false"
      - "[BODY].needsDbUpgrade == false"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Applications: SearXNG (ENABLE_SEARXNG)
if [ "${ENABLE_SEARXNG:-false}" = "true" ]; then
  endpoints_block+='
  # Applications: SearXNG
  - name: SearXNG
    group: Applications
    url: "http://searxng-app:8080/healthz"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[BODY] == OK"
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
fi

# Management: Portainer (ENABLE_PORTAINER)
if [ "${ENABLE_PORTAINER:-false}" = "true" ]; then
  endpoints_block+='
  # Management: Portainer
  - name: Portainer
    group: Management
    url: "http://portainer:9000/api/system/status"
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[BODY].Version != \"\""
    alerts:
      - type: ntfy
        enabled: true
'
  count=$((count + 1))
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
