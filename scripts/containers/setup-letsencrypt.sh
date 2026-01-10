#!/bin/bash
trap "exit" INT

# Ensure the letsencrypt directory exists
mkdir -p ./composes/letsencrypt

# Check if acme.json exists, if not create it
if [ ! -f ./composes/letsencrypt/acme.json ]; then
    echo "[*] Creating acme.json..."
    touch ./composes/letsencrypt/acme.json
fi

# Set permissions to 600 (required by Traefik)
echo "[*] Setting permissions for acme.json to 600..."
chmod 600 ./composes/letsencrypt/acme.json

# If running as root (sudo), we might want to ensure ownership is correct if possible,
# but usually Traefik (running as root in container or user) needs to read it.
# Docker binds it. If the file is 600 owned by root on host, and container runs as root, it works.
# If container runs as user, it might fail unless uid matches. Traefik container usually runs as root unless specified.
# So root:root 600 is fine.

echo "[OK] LetsEncrypt setup completed."
