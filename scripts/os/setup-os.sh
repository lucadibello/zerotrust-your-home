#!/bin/bash
trap "exit" INT

## -- DOWNLOAD AND INSTALL UPDATES
echo "[*] Updating and upgrading the system..."

# Update the system and install updates
sudo apt update && sudo apt upgrade -y

## -- INSTALL REQUIREMENTS
echo "[*] Installing requirements..."

# Install base requirements:
# - make (to use project utility file)
# - apparmor (Docker requirement)
# - ntp server (system clock synchronization)
# - unattended-upgrades
# - iptables-persistent
# - pam_passwdqc module to enforce strong passwords
# - sqlite3 (required to provision uptime-kuma database)
sudo apt install -y make apparmor systemd-timesyncd \
  unattended-upgrades iptables-persistent \
  libpam-passwdqc sqlite3 ca-certificates curl gnupg

## -- INSTALL DOCKER FROM OFFICIAL REPOSITORY
echo "[*] Setting up Docker official repository..."

# Remove old/conflicting Docker packages if present
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y $pkg 2>/dev/null || true
done

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update and install Docker Engine with Compose plugin
echo "[*] Installing Docker Engine and Compose plugin..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify installation
echo "[*] Docker version:"
docker --version
echo "[*] Docker Compose version:"
docker compose version

## -- INSTALL IMMICH-GO
echo "[*] Installing immich-go..."
IMMICH_GO_VERSION="v0.31.0"
curl -L -o immich-go.tar.gz "https://github.com/simulot/immich-go/releases/download/${IMMICH_GO_VERSION}/immich-go_Linux_x86_64.tar.gz"
tar -xzf immich-go.tar.gz
sudo mv immich-go /usr/local/bin/immich-go
sudo chmod +x /usr/local/bin/immich-go
rm immich-go.tar.gz
echo "[*] immich-go installed successfully"

## -- START REQUIRED SERVICES

# Enable unattended-upgrades
echo "[*] Starting unattended-upgrades service..."
sudo systemctl enable unattended-upgrades
sudo systemctl start unattended-upgrades

# Start + enable systemd-timesyncd service
echo "[*] Starting systemd-timesyncd service..."
sudo systemctl start systemd-timesyncd.service
sudo systemctl enable systemd-timesyncd.service

# Enable and start Docker service
echo "[*] Starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

## -- ADDITIONAL SERVICE SETUPS

# Enable ntp synchronization
echo "[*] Setting up time synchronization..."
sudo timedatectl set-ntp true

## -- SETUP CORRECT UDP BUFFER SIZE
# NOTE: This is required for cloudflare tunnel to work properly
# Link: https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
sudo sysctl -w net.core.rmem_max=7500000
sudo sysctl -w net.core.wmem_max=7500000

echo "[*] OS setup completed successfully!"
