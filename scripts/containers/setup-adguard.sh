#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if AdGuard Home is not enabled
if [ "${ENABLE_ADGUARD:-false}" != "true" ]; then
  echo "[*] AdGuard Home is disabled, skipping setup..."
  exit 0
fi

# Ensure directories exist
mkdir -p "$PROJECT_ROOT/composes/adguard/work" "$PROJECT_ROOT/composes/adguard/conf"

# Ensure external networks exist with correct subnets
ensure_network "traefik-network"
ensure_network "dns-network" "10.53.0.0/24"

# Pre-configure AdGuard Home if not already configured
ADGUARD_CONF="$PROJECT_ROOT/composes/adguard/conf/AdGuardHome.yaml"
DNS_DOMAIN="${DNS_DOMAIN:-home.lucadibello.ch}"
PRIMARY_DNS="${PRIMARY_DNS:-192.168.0.253}"
LOCAL_NETWORK="${LOCAL_NETWORK:-192.168.0.0/24}"

if [ ! -f "$ADGUARD_CONF" ]; then
  cat <<EOF >"$ADGUARD_CONF"
schema_version: 29
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  upstream_dns:
    - '[/${DNS_DOMAIN}/]${PRIMARY_DNS}'
    - https://dns.cloudflare.com/dns-query
    - https://dns.quad9.net/dns-query
  bootstrap_dns:
    - 9.9.9.9
    - 1.1.1.1
  blocking_mode: default
  ratelimit: 0
  filtering_enabled: true
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
    - 10.0.0.0/8
    - 172.16.0.0/12
    - ${LOCAL_NETWORK}
    - 100.64.0.0/10
http:
  address: 0.0.0.0:80
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
EOF
  echo "[*] Initialized pre-configured AdGuard Home configuration (AdGuardHome.yaml)"
fi

# Ensure trusted_proxies, local upstream forwarder, and client access rules in existing configuration
set +e
python3 "$PROJECT_ROOT/scripts/containers/configure-adguard.py" "$ADGUARD_CONF" "$DNS_DOMAIN" "$PRIMARY_DNS" "$LOCAL_NETWORK"
exit_code=$?
set -e

if [ $exit_code -eq 3 ]; then
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -v "$PROJECT_ROOT/composes/adguard/conf":/conf alpine sh -c 'cp /conf/AdGuardHome.yaml.tmp /conf/AdGuardHome.yaml && rm -f /conf/AdGuardHome.yaml.tmp' >/dev/null 2>&1 || true
    echo "[OK] Applied AdGuard configuration update to AdGuardHome.yaml via Docker"
    exit_code=2
  fi
fi

if [ $exit_code -eq 2 ]; then
  if command -v docker >/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^adguard$'; then
      echo "[*] Reloading AdGuard container with updated configuration..."
      docker restart adguard >/dev/null 2>&1 || true
      echo "[OK] AdGuard reloaded successfully"
    fi
  fi
fi

# Automatically sync valid TLS certificates from Traefik
if [ -f "$PROJECT_ROOT/scripts/containers/sync-adguard-certs.sh" ]; then
  bash "$PROJECT_ROOT/scripts/containers/sync-adguard-certs.sh" || true
fi

echo "[OK] AdGuard Home setup completed"
