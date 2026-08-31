#!/bin/bash
set -euo pipefail
trap "exit" INT

# Load common features
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env"

# Skip if DNS is disabled
if [ "${ENABLE_DNS:-true}" != "true" ]; then
  echo "[*] DNS (BIND9) is disabled, skipping setup..."
  exit 0
fi

# Ensure required directories exist
DNS_CONFIG_DIR="$PROJECT_ROOT/composes/dns/config"
mkdir -p "$DNS_CONFIG_DIR" \
         "$PROJECT_ROOT/composes/dns/cache" \
         "$PROJECT_ROOT/composes/dns/records"

# Create external Docker network for DNS
docker network create dns-network >/dev/null 2>&1 || true

# Generate zone filename (e.g., "example.com" becomes "example-com")
filename=$(echo "$DNS_DOMAIN" | sed 's/\./-/g')
serial=$(date +%Y%m%d%H)
soa_email=$(echo "$DNS_EMAIL" | sed 's/@/./g')

echo "[*] Generating BIND9 DNS zone and named.conf for $DNS_DOMAIN..."

# 1. Render Zone File
ZONE_TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/zone.template"
ZONE_TARGET="$DNS_CONFIG_DIR/$filename.zone"

render_template "$ZONE_TEMPLATE" "$ZONE_TARGET" \
  DOMAIN="$DNS_DOMAIN" \
  EMAIL="$soa_email" \
  IP_ADDRESS="$IP_ADDRESS" \
  SERIAL="$serial"

# 2. Build the ACL block for local subnets
local_subnets=""
if command -v nmcli >/dev/null 2>&1; then
  local_subnets=$(nmcli | grep route4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | sort -u | sed 's|$|;|g' || true)
fi

# Fallback: Detect subnets via iproute2
if [ -z "$local_subnets" ] && command -v ip >/dev/null 2>&1; then
  local_subnets=$(ip -4 route show 2>/dev/null | grep -v 'default' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | sort -u | sed 's|$|;|g' || true)
fi

# Fallback: Use LOCAL_NETWORK defined in .env
if [ -z "$local_subnets" ] && [ -n "${LOCAL_NETWORK:-}" ]; then
  local_subnets="${LOCAL_NETWORK};"
fi

acl_block="acl internal {\n"
if [ -n "$local_subnets" ]; then
  for subnet in $local_subnets; do
    acl_block+="    ${subnet}\n"
  done
else
  acl_block+="    127.0.0.0/8;\n    192.168.0.0/16;\n    10.0.0.0/8;\n    172.16.0.0/12;\n"
fi
acl_block+="};\n"

# 3. Render named.conf from template
NAMED_TEMPLATE="$PROJECT_ROOT/scripts/containers/templates/named.conf.template"
NAMED_TARGET="$DNS_CONFIG_DIR/named.conf"

render_template "$NAMED_TEMPLATE" "$NAMED_TARGET" \
  DOMAIN="$DNS_DOMAIN" \
  FILENAME="$filename"

# 4. Prepend ACL block to named.conf
temp_named="$NAMED_TARGET.tmp"
printf "%b\n" "$acl_block" > "$temp_named"
cat "$NAMED_TARGET" >> "$temp_named"
mv "$temp_named" "$NAMED_TARGET"

echo "[OK] BIND9 DNS setup completed"
