#!/bin/bash
trap "exit" INT

# Create traefik network
docker network create traefik-network || true

echo "[OK] Traefik setup complete"
