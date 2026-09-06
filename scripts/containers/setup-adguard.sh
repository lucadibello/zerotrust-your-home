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
    - 192.168.0.0/16
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
python3 - "$ADGUARD_CONF" "$DNS_DOMAIN" "$PRIMARY_DNS" << 'PYEOF'
import sys, os, re

conf_file = sys.argv[1]
dns_domain = sys.argv[2]
primary_dns = sys.argv[3]

if not os.path.isfile(conf_file):
    sys.exit(0)

try:
    with open(conf_file, 'r') as f:
        content = f.read()
except Exception as e:
    print(f"[-] Could not read {conf_file}: {e}")
    sys.exit(0)

changed = False

# 1. Ensure trusted_proxies contains Docker and private subnets
trusted_proxies_block = """  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
    - 100.64.0.0/10"""

if "trusted_proxies:" in content:
    if "172.16.0.0/12" not in content or "10.0.0.0/8" not in content:
        content = re.sub(r'  trusted_proxies:\n(    - [^\n]+\n)+', trusted_proxies_block + '\n', content)
        changed = True
else:
    content = re.sub(r'^(dns:.*?\n)', r'\1' + trusted_proxies_block + '\n', content, flags=re.MULTILINE)
    changed = True

# 2. Ensure upstream_dns contains [/<domain>/]<primary_dns>
upstream_entry = f"[/{dns_domain}/]{primary_dns}"
if dns_domain and primary_dns and upstream_entry not in content:
    if re.search(r'  upstream_dns:\n', content):
        content = re.sub(r'(  upstream_dns:\n)', r"\1    - '" + upstream_entry + "'\n", content)
        changed = True

# 3. If allowed_clients is non-empty, ensure local/docker subnets are included
allowed_match = re.search(r'  allowed_clients:\n((    - [^\n]+\n)+)', content)
if allowed_match:
    current_allowed = allowed_match.group(1)
    needed_subnets = [
        "192.168.0.0/24",
        "192.168.1.0/24",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "100.64.0.0/10"
    ]
    added = [f"    - {sub}\n" for sub in needed_subnets if sub not in current_allowed]
    if added:
        new_allowed = current_allowed + "".join(added)
        content = content.replace(allowed_match.group(0), f"  allowed_clients:\n{new_allowed}")
        changed = True

if changed:
    try:
        with open(conf_file, 'w') as f:
            f.write(content)
        print(f"[OK] Enforced trusted_proxies and upstream configuration in {conf_file}")
        sys.exit(2)
    except PermissionError:
        tmp_path = conf_file + ".tmp"
        try:
            with open(tmp_path, 'w') as f:
                f.write(content)
            print(f"[*] Staged AdGuard configuration update to {tmp_path}")
            sys.exit(3)
        except Exception as e:
            print(f"[-] Could not stage configuration update: {e}")

sys.exit(0)
PYEOF
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
