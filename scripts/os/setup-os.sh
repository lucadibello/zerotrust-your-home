#!/bin/bash
trap "exit" INT

# Source common functions if available
if [ -f "./scripts/common.sh" ]; then
  source ./scripts/common.sh
fi

# Set non-interactive mode for Debian/Ubuntu apt packages
export DEBIAN_FRONTEND=noninteractive

# Pre-seed debconf selections for iptables-persistent to avoid interactive prompts
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections 2>/dev/null || true
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections 2>/dev/null || true

## -- DOWNLOAD AND INSTALL UPDATES
echo "[*] Updating and upgrading the system..."

# Update the system and install updates
sudo apt-get update && sudo apt-get upgrade -y

## -- INSTALL REQUIREMENTS
echo "[*] Installing requirements..."

# Install base requirements:
# - make (to use project utility file)
# - apparmor (Docker requirement)
# - systemd-timesyncd (system clock synchronization)
# - unattended-upgrades
# - iptables-persistent
# - pam_passwdqc module to enforce strong passwords
# - sqlite3 (required to provision uptime-kuma database)
# - network-manager & iproute2 (robust network configuration)
# - ca-certificates, curl, gnupg (Docker and tooling setup)
sudo apt-get install -y make apparmor systemd-timesyncd \
  unattended-upgrades iptables-persistent \
  libpam-passwdqc sqlite3 ca-certificates curl gnupg \
  network-manager iproute2 pciutils

## -- PROXMOX / VIRTUAL MACHINE DETECTIONS & GUEST AGENT
VIRT_TYPE="none"
if command -v detect_virtualization >/dev/null 2>&1; then
  VIRT_TYPE=$(detect_virtualization)
elif command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
fi

if [ "$VIRT_TYPE" = "kvm" ] || [ "$VIRT_TYPE" = "qemu" ] || [ "$VIRT_TYPE" = "bochs" ] || [ -e /dev/virtio-ports ] || ([ -f /sys/class/dmi/id/sys_vendor ] && grep -qiE "qemu|kvm|proxmox|bochs" /sys/class/dmi/id/sys_vendor 2>/dev/null); then
  echo "[*] Virtualized environment detected ($VIRT_TYPE / Proxmox VM)."
  echo "[*] Installing and enabling QEMU Guest Agent for Proxmox VE integration..."
  sudo apt-get install -y qemu-guest-agent
  sudo systemctl enable qemu-guest-agent 2>/dev/null || true
  sudo systemctl start qemu-guest-agent 2>/dev/null || true
fi

## -- INSTALL DOCKER FROM OFFICIAL REPOSITORY
echo "[*] Setting up Docker official repository..."

# Remove old/conflicting Docker packages if present
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y $pkg 2>/dev/null || true
done

# Detect Linux distribution family (Debian vs Ubuntu)
DOCKER_DISTRO="debian"
if command -v detect_linux_distro >/dev/null 2>&1; then
  DOCKER_DISTRO=$(detect_linux_distro)
elif [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "${ID:-}" = "ubuntu" ] || [[ "${ID_LIKE:-}" =~ "ubuntu" ]]; then
    DOCKER_DISTRO="ubuntu"
  else
    DOCKER_DISTRO="debian"
  fi
fi

# Detect version codename
CODENAME=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  CODENAME="${VERSION_CODENAME:-}"
  if [ -z "$CODENAME" ]; then
    CODENAME="${UBUNTU_CODENAME:-}"
  fi
fi
if [ -z "$CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
  CODENAME=$(lsb_release -cs 2>/dev/null)
fi
if [ -z "$CODENAME" ]; then
  if [ "$DOCKER_DISTRO" = "ubuntu" ]; then
    CODENAME="jammy"
  else
    CODENAME="bookworm"
  fi
fi

echo "[*] Configuring Docker repository for ${DOCKER_DISTRO} (${CODENAME})..."

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DOCKER_DISTRO} ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo chmod 644 /etc/apt/sources.list.d/docker.list

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
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$ARCH" in
  amd64|x86_64)
    IMMICH_GO_ARCH="Linux_x86_64"
    ;;
  arm64|aarch64)
    IMMICH_GO_ARCH="Linux_arm64"
    ;;
  armhf|armv7l)
    IMMICH_GO_ARCH="Linux_armv7"
    ;;
  *)
    IMMICH_GO_ARCH="Linux_x86_64"
    ;;
esac

echo "[*] Downloading immich-go (${IMMICH_GO_ARCH})..."
curl -L -o immich-go.tar.gz "https://github.com/simulot/immich-go/releases/download/${IMMICH_GO_VERSION}/immich-go_${IMMICH_GO_ARCH}.tar.gz"
tar -xzf immich-go.tar.gz
sudo mv immich-go /usr/local/bin/immich-go
sudo chmod +x /usr/local/bin/immich-go
rm -f immich-go.tar.gz
echo "[*] immich-go installed successfully"

## -- START REQUIRED SERVICES

# Enable unattended-upgrades
echo "[*] Starting unattended-upgrades service..."
sudo systemctl enable unattended-upgrades 2>/dev/null || true
sudo systemctl start unattended-upgrades 2>/dev/null || true

# Start + enable systemd-timesyncd service
echo "[*] Starting systemd-timesyncd service..."
sudo systemctl start systemd-timesyncd.service 2>/dev/null || true
sudo systemctl enable systemd-timesyncd.service 2>/dev/null || true

# Enable and start Docker service
echo "[*] Starting Docker service..."
sudo systemctl enable docker 2>/dev/null || true
sudo systemctl start docker 2>/dev/null || true

## -- ADDITIONAL SERVICE SETUPS

# Enable ntp synchronization
echo "[*] Setting up time synchronization..."
sudo timedatectl set-ntp true 2>/dev/null || true

## -- SETUP CORRECT UDP BUFFER SIZE
# NOTE: This is required for cloudflare tunnel to work properly
# Link: https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
sudo sysctl -w net.core.rmem_max=7500000 2>/dev/null || true
sudo sysctl -w net.core.wmem_max=7500000 2>/dev/null || true

echo "[*] OS setup completed successfully!"

