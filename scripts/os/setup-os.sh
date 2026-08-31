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

# Clean up duplicate / conflicting Docker APT keyring configurations if present
if [ -f /etc/apt/keyrings/docker.gpg ] && [ -f /etc/apt/keyrings/docker.asc ]; then
  sudo rm -f /etc/apt/keyrings/docker.gpg
fi
if [ -f /etc/apt/sources.list.d/docker.list ] && [ -f /etc/apt/sources.list.d/docker.sources ]; then
  sudo rm -f /etc/apt/sources.list.d/docker.list
fi
if [ -f /etc/apt/sources.list.d/docker.list ] && [ -f /etc/apt/keyrings/docker.asc ]; then
  sudo sed -i 's|/etc/apt/keyrings/docker.gpg|/etc/apt/keyrings/docker.asc|g' /etc/apt/sources.list.d/docker.list 2>/dev/null || true
fi

## -- UPDATE PACKAGE LISTS
echo "[*] Updating package lists..."
sudo apt-get update

## -- INSTALL BASE REQUIREMENTS (ONLY MISSING PACKAGES)
echo "[*] Checking base requirements..."

required_pkgs=(
  make
  apparmor
  systemd-timesyncd
  unattended-upgrades
  iptables-persistent
  libpam-passwdqc
  sqlite3
  ca-certificates
  curl
  gnupg
  network-manager
  iproute2
  pciutils
  cron
  openssl
  zip
  unzip
)

missing_pkgs=()
for pkg in "${required_pkgs[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing_pkgs+=("$pkg")
  fi
done

if [ ${#missing_pkgs[@]} -gt 0 ]; then
  echo "[*] Installing missing base packages: ${missing_pkgs[*]}..."
  sudo apt-get install -y "${missing_pkgs[@]}"
else
  echo "[*] Base requirements are already installed."
fi


## -- PROXMOX / VIRTUAL MACHINE DETECTIONS & GUEST AGENT
VIRT_TYPE="none"
if command -v detect_virtualization >/dev/null 2>&1; then
  VIRT_TYPE=$(detect_virtualization)
elif command -v systemd-detect-virt >/dev/null 2>&1; then
  VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
fi

if [ "$VIRT_TYPE" = "kvm" ] || [ "$VIRT_TYPE" = "qemu" ] || [ "$VIRT_TYPE" = "bochs" ] || [ -e /dev/virtio-ports ] || ([ -f /sys/class/dmi/id/sys_vendor ] && grep -qiE "qemu|kvm|proxmox|bochs" /sys/class/dmi/id/sys_vendor 2>/dev/null); then
  echo "[*] Virtualized environment detected ($VIRT_TYPE / Proxmox VM)."
  if dpkg -s qemu-guest-agent >/dev/null 2>&1 || command -v qemu-ga >/dev/null 2>&1; then
    echo "[*] QEMU Guest Agent is already installed."
  else
    echo "[*] Installing QEMU Guest Agent for Proxmox VE integration..."
    sudo apt-get install -y qemu-guest-agent
  fi
  sudo systemctl enable qemu-guest-agent 2>/dev/null || true
  sudo systemctl start qemu-guest-agent 2>/dev/null || true
fi

## -- INSTALL DOCKER FROM OFFICIAL REPOSITORY (ONLY IF NOT PRESENT)
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "[*] Docker Engine and Compose plugin are already installed:"
  echo "    - $(docker --version)"
  echo "    - $(docker compose version)"
else
  echo "[*] Docker is not installed or missing compose plugin. Setting up Docker repository..."

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

  # Standardize on Docker's official modern key format (docker.asc)
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
  sudo curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Remove any conflicting older docker source definitions before adding the canonical list file
  sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources

  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
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
fi




## -- START REQUIRED SERVICES

# Enable unattended-upgrades
echo "[*] Ensuring unattended-upgrades service is running..."
sudo systemctl enable unattended-upgrades 2>/dev/null || true
if ! systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
  sudo systemctl start unattended-upgrades 2>/dev/null || true
fi

# Start + enable systemd-timesyncd service
echo "[*] Ensuring systemd-timesyncd service is running..."
sudo systemctl enable systemd-timesyncd.service 2>/dev/null || true
if ! systemctl is-active --quiet systemd-timesyncd.service 2>/dev/null; then
  sudo systemctl start systemd-timesyncd.service 2>/dev/null || true
fi

# Configure Docker daemon default DNS
p_dns="${PRIMARY_DNS:-192.168.0.253}"
s_dns="${SECONDARY_DNS:-1.1.1.1}"
sudo mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  echo "{\"dns\": [\"$p_dns\", \"$s_dns\"]}" | sudo tee /etc/docker/daemon.json >/dev/null
fi

# Enable and start Docker service
if command -v docker >/dev/null 2>&1; then
  echo "[*] Ensuring Docker service is running..."
  sudo systemctl enable docker 2>/dev/null || true
  if ! systemctl is-active --quiet docker 2>/dev/null; then
    sudo systemctl start docker 2>/dev/null || true
  fi
fi

# Enable and start Cron service
if command -v crontab >/dev/null 2>&1 || dpkg -s cron >/dev/null 2>&1; then
  echo "[*] Ensuring Cron service is running..."
  sudo systemctl enable cron 2>/dev/null || true
  if ! systemctl is-active --quiet cron 2>/dev/null; then
    sudo systemctl start cron 2>/dev/null || true
  fi
fi


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


