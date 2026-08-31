#!/bin/bash
set -euo pipefail
trap "exit" INT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PROJECT_ROOT/scripts/common.sh"

# Load .env file
load_env "$PROJECT_ROOT/.env"

WORK_DIR="$PROJECT_ROOT/.tmp/certs"
mkdir -p "$WORK_DIR"

CERT_CONF_TEMPLATE="$PROJECT_ROOT/scripts/certs/templates/certificate.conf.template"
CERT_CONF="$WORK_DIR/certificate.conf"

echo "[*] Rendering OpenSSL certificate configuration..."
render_template "$CERT_CONF_TEMPLATE" "$CERT_CONF" \
  COUNTRY="$TLS_CERTIFICATE_COUNTRY" \
  STATE="$TLS_CERTIFICATE_STATE" \
  LOCALITY="$TLS_CERTIFICATE_LOCALITY" \
  ORGANIZATION="$TLS_CERTIFICATE_ORGANIZATION" \
  IP_ADDRESS="$IP_ADDRESS"

cd "$WORK_DIR"

echo "[*] Creating CA certificate..."
openssl genrsa -out ca.key 4096
openssl req -new -x509 -key ca.key -sha256 -subj "/C=${TLS_CERTIFICATE_COUNTRY}/ST=${TLS_CERTIFICATE_STATE}/OU=zigbee2mqtt" -days 365 -out ca.crt

echo "[*] Generating certificate keypair for MQTT service..."
openssl genrsa -out mqtt-service.key 4096
openssl req -new -key mqtt-service.key -out mqtt-service.csr -config "$CERT_CONF"
openssl x509 -req -in mqtt-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out mqtt-service.crt -days 365 -sha256 -extfile "$CERT_CONF" -extensions req_ext

echo "[*] Generating certificate keypair for Zigbee2MQTT service..."
openssl genrsa -out zigbee2mqtt-service.key 4096
openssl req -new -key zigbee2mqtt-service.key -out zigbee2mqtt-service.csr -config "$CERT_CONF"
openssl x509 -req -in zigbee2mqtt-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out zigbee2mqtt-service.crt -days 365 -sha256 -extfile "$CERT_CONF" -extensions req_ext

echo "[*] Generating certificate keypair for Home Assistant service..."
openssl genrsa -out hass-service.key 4096
openssl req -new -key hass-service.key -out hass-service.csr -config "$CERT_CONF"
openssl x509 -req -in hass-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out hass-service.crt -days 365 -sha256 -extfile "$CERT_CONF" -extensions req_ext

echo "[*] Generating certificate keypair for Grouper service..."
openssl genrsa -out grouper-service.key 4096
openssl req -new -key grouper-service.key -out grouper-service.csr -config "$CERT_CONF"
openssl x509 -req -in grouper-service.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out grouper-service.crt -days 365 -sha256 -extfile "$CERT_CONF" -extensions req_ext

echo "[*] Deploying certificates to home automation services..."
HA_DIR="$PROJECT_ROOT/composes/home-assistant"
mkdir -p "$HA_DIR/mosquitto/certs" \
         "$HA_DIR/zigbee2mqtt/certs" \
         "$HA_DIR/certs"

cp ca.crt "$HA_DIR/mosquitto/certs/ca.crt"
cp ca.crt "$HA_DIR/zigbee2mqtt/certs/ca.crt"
cp ca.crt "$HA_DIR/certs/ca.crt"

mv mqtt-service.key "$HA_DIR/mosquitto/certs/service.key"
mv mqtt-service.crt "$HA_DIR/mosquitto/certs/service.crt"

mv zigbee2mqtt-service.key "$HA_DIR/zigbee2mqtt/certs/service.key"
mv zigbee2mqtt-service.crt "$HA_DIR/zigbee2mqtt/certs/service.crt"

# Package Home Assistant client certificates for convenience
zip "$HA_DIR/certs/certs.zip" hass-service.key hass-service.crt ca.crt

cd "$PROJECT_ROOT"
rm -rf "$WORK_DIR"

echo "[OK] Certificate generation completed successfully."