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
ensure_network "dns-network" "172.28.0.0/16"

# Pre-configure AdGuard Home if not already configured
ADGUARD_CONF="$PROJECT_ROOT/composes/adguard/conf/AdGuardHome.yaml"
if [ ! -f "$ADGUARD_CONF" ]; then
  cat <<'EOF' > "$ADGUARD_CONF"
schema_version: 29
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - https://dns.quad9.net/dns-query
  bootstrap_dns:
    - 9.9.9.9
    - 1.1.1.1
  blocking_mode: default
  ratelimit: 0
  filtering_enabled: true
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

echo "[OK] AdGuard Home setup completed"
