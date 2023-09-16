#!/bin/bash

# Create required directories (ignore if already exists)
mkdir -p ./composes/bind9/cache ./composes/bind9/records ./composes/bind9/config ./.tmp/bind9 || true

# Load environment variables
set -a
source .env
set +a

# Now, create a zone file leveraging the environment variable settings

# Replace <DOMAIN> with the domain name ($DNS_DOMAIN). The file name should replace dots with dashes.
# For example, if $DNS_DOMAIN is "example.com", the file name should be "example-com".
filename=$(echo $DNS_DOMAIN | sed 's/\./-/g')

echo "[*] Creating zone file for $DNS_DOMAIN with filename $filename"

# Replace <IP_ADDRESS> with the IP address of the server ($IP_ADDRESS)
sed "s/<IP_ADDRESS>/$IP_ADDRESS/g" ./scripts/containers/templates/zone.template | sudo tee ./.tmp/bind9/$filename.zone > /dev/null

# Replace <DOMAIN> with the domain name ($DNS_DOMAIN)
sed -i "s/<DOMAIN>/$DNS_DOMAIN/g" ./.tmp/bind9/$filename.zone

# Replace <EMAIL> with the email address of the administrator ($DNS_EMAIL)
# Replace '@' with . in EMAIL
DNS_EMAIL=$(echo $DNS_EMAIL | sed 's/@/./g')

sed -i "s/<EMAIL>/$DNS_EMAIL/g" ./.tmp/bind9/$filename.zone

# Replace <IP_ADDRESS> with the IP address of the server ($IP_ADDRESS)
sed -i "s/<IP_ADDRESS>/$IP_ADDRESS/g" ./.tmp/bind9/$filename.zone

# Compute a new serial number for the zone file
serial=$(date +%Y%m%d%H)
sed -i "s/<SERIAL>/$serial/g" ./.tmp/bind9/$filename.zone

# Now, create the named.conf file
echo "[*] Creating named.conf file for $DNS_DOMAIN"

## Replace <DOMAIN> with the domain name ($DNS_DOMAIN)
sed "s/<DOMAIN>/$DNS_DOMAIN/g" ./scripts/containers/templates/named.conf.template | sudo tee ./.tmp/bind9/named.conf > /dev/null

## REPLACAE <FILENAME> with the filename of the zone file
sed -i "s/<FILENAME>/$filename/g" ./.tmp/bind9/named.conf

## Now, look for all the local network addresses
local_subnets=$(sudo nmcli | grep route4 | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[1-9]{1,2}' | sed 's|$|;|g')

## Write "acl internal {" to the top of the file
sed -i "1s|^|acl internal {\n|g" ./.tmp/bind9/named.conf

## Close the acl internal with "};"
sed -i "2s|^|};\n|g" ./.tmp/bind9/named.conf

for subnet in $local_subnets
do
    ## Add the subnet to the acl internal
    sed -i "2s|^|    $subnet\n|g" ./.tmp/bind9/named.conf
done

# Now, move the zone file to the records directory
mv ./.tmp/bind9/$filename.zone ./composes/bind9/config/$filename.zone
mv ./.tmp/bind9/named.conf ./composes/bind9/config/named.conf

# Remove temporary directory
rm -rf ./.tmp/bind9