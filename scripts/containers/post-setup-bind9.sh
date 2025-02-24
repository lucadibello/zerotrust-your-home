#!/bin/bash
# This script generates configuration files for Bind9
# It is now cross‑platform: Linux and macOS.

# Load common features
source ./scripts/common.sh

# Create required directories (ignore errors if they already exist)
mkdir -p ./composes/bind9/cache \
  ./composes/bind9/records \
  ./composes/bind9/config \
  ./.tmp/bind9 || true

# Create external Docker network (ignore if already exists)
sudo docker network create dns-network || true

# Load environment variables
set -a
source .env
set +a

# Generate a filename by replacing dots in $DNS_DOMAIN with dashes.
# For example, "example.com" becomes "example-com"
filename=$(echo "$DNS_DOMAIN" | sed 's/\./-/g')
echo "[*] Creating zone file for $DNS_DOMAIN with filename $filename"

# Create the zone file from template:
# 1. Replace <IP_ADDRESS> with $IP_ADDRESS
sed "s/<IP_ADDRESS>/$IP_ADDRESS/g" ./scripts/containers/templates/zone.template |
  sudo tee ./.tmp/bind9/$filename.zone >/dev/null

# 2. Replace <DOMAIN> with $DNS_DOMAIN
$SED_INPLACE "s/<DOMAIN>/$DNS_DOMAIN/g" ./.tmp/bind9/$filename.zone

# 3. Replace <EMAIL> with $DNS_EMAIL (with '@' replaced by '.')
DNS_EMAIL=$(echo "$DNS_EMAIL" | sed 's/@/./g')
$SED_INPLACE "s/<EMAIL>/$DNS_EMAIL/g" ./.tmp/bind9/$filename.zone

# 4. (Again) Replace <IP_ADDRESS> with $IP_ADDRESS (if needed)
$SED_INPLACE "s/<IP_ADDRESS>/$IP_ADDRESS/g" ./.tmp/bind9/$filename.zone

# 5. Replace <SERIAL> with a new serial (based on the current date and hour)
serial=$(date +%Y%m%d%H)
$SED_INPLACE "s/<SERIAL>/$serial/g" ./.tmp/bind9/$filename.zone

# --- Now create the named.conf file ---
echo "[*] Creating named.conf file for $DNS_DOMAIN"

# 1. Replace <DOMAIN> with $DNS_DOMAIN in the template
sed "s/<DOMAIN>/$DNS_DOMAIN/g" ./scripts/containers/templates/named.conf.template |
  sudo tee ./.tmp/bind9/named.conf >/dev/null

# 2. Replace <FILENAME> with the zone file name (without dots)
$SED_INPLACE "s/<FILENAME>/$filename/g" ./.tmp/bind9/named.conf

# --- Build the ACL block for local subnets ---
if command -v nmcli >/dev/null 2>&1; then
  # Extract local subnets (each ending with a semicolon)
  local_subnets=$(sudo nmcli | grep route4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | sed 's|$|;|g')
else
  echo "[!] nmcli not found. Skipping local subnet detection."
  local_subnets=""
fi

# Construct the ACL block as a variable
acl_block="acl internal {\n"
if [ -n "$local_subnets" ]; then
  for subnet in $local_subnets; do
    acl_block+="    ${subnet}\n"
  done
fi
acl_block+="};\n"

# Prepend the ACL block to the named.conf file in a portable way
(
  echo -e "$acl_block"
  cat ./.tmp/bind9/named.conf
) | sudo tee ./.tmp/bind9/named.conf >/dev/null

# --- Finalize: move configuration files to the proper directory ---
mv ./.tmp/bind9/"$filename".zone ./composes/bind9/config/"$filename".zone
mv ./.tmp/bind9/named.conf ./composes/bind9/config/named.conf

# Remove the temporary directory
rm -rf ./.tmp/bind9

echo "[OK] setup configured successfully"

