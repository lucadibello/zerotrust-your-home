#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"
load_env "$PROJECT_ROOT/.env"

if [ "${ENABLE_ADGUARD:-false}" != "true" ]; then
  exit 0
fi

ACME_FILE="$PROJECT_ROOT/composes/traefik/letsencrypt/acme.json"
CERTS_DIR="$PROJECT_ROOT/composes/adguard/conf/certs"
CONF_FILE="$PROJECT_ROOT/composes/adguard/conf/AdGuardHome.yaml"
DOMAIN="adguard.${DNS_DOMAIN:-home.lucadibello.ch}"

if [ ! -f "$ACME_FILE" ]; then
  log "[*] Traefik acme.json not found, skipping AdGuard certificate sync..."
  exit 0
fi

mkdir -p "$CERTS_DIR"

set +e
python3 - "$ACME_FILE" "$CONF_FILE" "$CERTS_DIR" "$DOMAIN" << 'PYEOF'
import sys, json, base64, os, re

acme_file = sys.argv[1]
conf_file = sys.argv[2]
certs_dir = sys.argv[3]
target_domain = sys.argv[4]

try:
    with open(acme_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"[-] Could not parse acme.json: {e}")
    sys.exit(0)

matched_cert = None
for cert_entry in data.get('letsencrypt', {}).get('Certificates', []):
    domain_info = cert_entry.get('domain', {})
    main_domain = domain_info.get('main', '')
    sans = domain_info.get('sans', [])
    if main_domain == target_domain or target_domain in sans:
        matched_cert = cert_entry
        break

# Fallback: check for wildcard domain (e.g. *.home.lucadibello.ch)
if not matched_cert:
    parts = target_domain.split('.', 1)
    if len(parts) > 1:
        wildcard = f"*.{parts[1]}"
        for cert_entry in data.get('letsencrypt', {}).get('Certificates', []):
            domain_info = cert_entry.get('domain', {})
            main_domain = domain_info.get('main', '')
            sans = domain_info.get('sans', [])
            if main_domain == wildcard or wildcard in sans:
                matched_cert = cert_entry
                break

if not matched_cert:
    print(f"[*] Certificate for {target_domain} not yet generated in acme.json")
    sys.exit(0)

try:
    cert_pem = base64.b64decode(matched_cert['certificate']).decode('utf-8')
    key_pem = base64.b64decode(matched_cert['key']).decode('utf-8')
except Exception as e:
    print(f"[-] Error decoding certificate from acme.json: {e}")
    sys.exit(1)

fullchain_path = os.path.join(certs_dir, 'fullchain.pem')
privkey_path = os.path.join(certs_dir, 'privkey.pem')

# Check if certificates actually changed
cert_changed = True
if os.path.exists(fullchain_path) and os.path.exists(privkey_path):
    try:
        with open(fullchain_path, 'r') as f:
            old_cert = f.read()
        with open(privkey_path, 'r') as f:
            old_key = f.read()
        if old_cert == cert_pem and old_key == key_pem:
            cert_changed = False
    except Exception:
        pass

if cert_changed:
    with open(fullchain_path, 'w') as f:
        f.write(cert_pem)
    with open(privkey_path, 'w') as f:
        f.write(key_pem)
    os.chmod(fullchain_path, 0o644)
    os.chmod(privkey_path, 0o600)
    print(f"[OK] Extracted valid TLS certificate for {target_domain} to {certs_dir}")
else:
    print(f"[*] TLS certificate for {target_domain} is up-to-date")

# Update AdGuardHome.yaml TLS configuration if the file exists
if os.path.isfile(conf_file):
    try:
        with open(conf_file, 'r') as f:
            content = f.read()

        new_tls = f"""tls:
  enabled: true
  server_name: {target_domain}
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  certificate_chain: ""
  private_key: ""
  certificate_path: /opt/adguardhome/conf/certs/fullchain.pem
  private_key_path: /opt/adguardhome/conf/certs/privkey.pem
  strict_sni_check: false"""

        if re.search(r'^tls:.*?(?=\n\S|\Z)', content, re.MULTILINE | re.DOTALL):
            updated = re.sub(r'^tls:.*?(?=\n\S|\Z)', new_tls, content, flags=re.MULTILINE | re.DOTALL)
        else:
            updated = content.rstrip() + '\n' + new_tls + '\n'

        if updated != content:
            try:
                with open(conf_file, 'w') as f:
                    f.write(updated)
                print(f"[OK] Enabled TLS encryption in {conf_file}")
                sys.exit(2) # Code 2: config updated directly
            except PermissionError:
                tmp_path = os.path.join(certs_dir, 'AdGuardHome.yaml.tmp')
                with open(tmp_path, 'w') as f:
                    f.write(updated)
                print(f"[*] Staged TLS update to {tmp_path}")
                sys.exit(3) # Code 3: config staged, needs container copy
    except Exception as e:
        print(f"[-] Warning: Failed to update {conf_file}: {e}")

if cert_changed:
    sys.exit(2) # Reload needed
PYEOF
exit_code=$?
set -e

if [ $exit_code -eq 3 ]; then
  if command -v docker >/dev/null 2>&1; then
    docker run --rm -v "$PROJECT_ROOT/composes/adguard/conf":/conf alpine sh -c 'cp /conf/certs/AdGuardHome.yaml.tmp /conf/AdGuardHome.yaml && rm -f /conf/certs/AdGuardHome.yaml.tmp' >/dev/null 2>&1 || true
    log "[OK] Applied TLS encryption configuration to AdGuardHome.yaml via Docker"
    exit_code=2
  fi
fi

if [ $exit_code -eq 2 ]; then
  if command -v docker >/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^adguard$'; then
      log "[*] Reloading AdGuard container with updated TLS certificate..."
      docker restart adguard >/dev/null 2>&1 || true
      log "[OK] AdGuard reloaded successfully"
    fi
  fi
fi
