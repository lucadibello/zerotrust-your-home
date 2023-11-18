#!/bin/bash

# Load .env file
set -a
source .env
set +a

# Create temporary directory
mkdir -p ./composes/certs ./.tmp/certs || true

# Now, generate certificate.conf file in ./tmp/certs directory
sed "s/<COUNTRY>/$TLS_CERTIFICATE_COUNTRY/g" ./scripts/certs/templates/certificate.conf.template | sudo tee ./.tmp/certs/certificate.conf > /dev/null
sed -i "s/<STATE>/$TLS_CERTIFICATE_STATE/g" ./.tmp/certs/certificate.conf
sed -i "s/<LOCALITY>/$TLS_CERTIFICATE_LOCALITY/g" ./.tmp/certs/certificate.conf
sed -i "s/<ORGANIZATION>/$TLS_CERTIFICATE_ORGANIZATION/g" ./.tmp/certs/certificate.conf
sed -i "s/<IP_ADDRESS>/$IP_ADDRESS/g" ./.tmp/certs/certificate.conf

# Move to composes directory
mv ./.tmp/certs/certificate.conf ./composes/certs/certificate.conf

# Remove temporary directory
rm -rf ./.tmp/certs

# Enter project dir
cd composes

echo "[*] Creating CA certificate..."
openssl genrsa -out ca.key 4096
openssl req -new -x509 -key ca.key -sha256 -subj "/C=CH/ST=CH/OU=zigbee2mqtt" -days 365 -out ca.crt

echo "[*] Generating certificate keypair for MQTT service..."
openssl genrsa -out mqtt-service.key 4096
openssl req -new -key mqtt-service.key -out mqtt-service.csr -config certs/certificate.conf
openssl x509 -req -in mqtt-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out mqtt-service.crt -days 365 -sha256 -extfile certs/certificate.conf -extensions req_ext

echo "[*] Generating certificate keypair for Zigbee2MQTT service..."
openssl genrsa -out zigbee2mqtt-service.key 4096
openssl req -new -key zigbee2mqtt-service.key -out zigbee2mqtt-service.csr -config certs/certificate.conf
openssl x509 -req -in zigbee2mqtt-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out zigbee2mqtt-service.crt -days 365 -sha256 -extfile certs/certificate.conf -extensions req_ext

echo "[*] Generating certificate keypair for Home Assistant service..."
openssl genrsa -out hass-service.key 4096
openssl req -new -key hass-service.key -out hass-service.csr -config certs/certificate.conf
openssl x509 -req -in hass-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out hass-service.crt -days 365 -sha256 -extfile certs/certificate.conf -extensions req_ext

echo "[*] Generating certificate keypair for Grouper service..."
openssl genrsa -out grouper-service.key 4096
openssl req -new -key grouper-service.key -out grouper-service.csr -config certs/certificate.conf
openssl x509 -req -in grouper-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out grouper-service.crt -days 365 -sha256 -extfile certs/certificate.conf -extensions req_ext

echo "[*] Creating required directories..."
mkdir -p mosquitto/certs
mkdir -p zigbee2mqtt/certs
mkdir -p home-assistant/certs
mkdir -p grouper/certs

echo "[*] Copying files to services"
cp ca.crt mosquitto/certs/ca.crt
cp ca.crt zigbee2mqtt/certs/ca.crt
cp ca.crt grouper/certs/ca.crt
mv mqtt-service.key mosquitto/certs/service.key
mv mqtt-service.crt mosquitto/certs/service.crt
mv zigbee2mqtt-service.key zigbee2mqtt/certs/service.key
mv zigbee2mqtt-service.crt zigbee2mqtt/certs/service.crt
mv grouper-service.key grouper/certs/service.key
mv grouper-service.crt grouper/certs/service.crt

# Zip home assistant certificates to be easily copied to the client machine
zip home-assistant/certs/certs.zip hass-service.key hass-service.crt ca.crt

echo "[*] Cleaning up..."
rm ca.crt
rm ca.key
rm ca.srl
rm mqtt-service.csr
rm zigbee2mqtt-service.csr
rm hass-service.csr
rm hass-service.crt
rm hass-service.key
rm grouper-service.csr

# Go back to project root
cd ..