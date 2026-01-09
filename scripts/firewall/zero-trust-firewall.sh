#!/bin/bash

# Zero Trust Firewall Configuration Script (Idempotent)
# This script can be safely re-run to update firewall rules.

set -e

# Load .env file
if [ -f .env ]; then
  set -a
  source .env
  set +a
elif [ -f ../.env ]; then
  set -a
  source ../.env
  set +a
else
  echo "[!] .env file not found. Please run from project root."
  exit 1
fi

# Validate required variables
if [ -z "$LOCAL_NETWORK" ] || [ -z "$IF" ]; then
  echo "[!] Required variables LOCAL_NETWORK and IF must be set in .env"
  exit 1
fi

# Print configuration and ask for confirmation
echo "=============================================="
echo "   Zero Trust Firewall Configuration          "
echo "=============================================="
echo ""
echo "Configuration:"
echo "  - Local network: $LOCAL_NETWORK"
echo "  - Primary interface: $IF"
echo "  - Enable SSH from local network: $ALLOW_LOCAL_SSH_ACCESS"
echo "  - Enable service access from local network: $ALLOW_LOCAL_SERVICES_ACCESS"
echo ""

# Check for --yes or headless mode
if [ "$1" != "-y" ] && [ "$1" != "--yes" ] && [ "$HEADLESS_MODE" != "true" ]; then
  echo "[!] This will update firewall settings."
  echo "[!] If connected via SSH, you may be disconnected (depending on settings)."
  read -p "Do you wish to continue? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting..."
    exit 1
  fi
fi

echo ""
echo "[*] Starting firewall configuration..."

# Helper function: Check if iptables chain exists
chain_exists() {
  sudo iptables -n -L "$1" >/dev/null 2>&1
}

# Helper function: Check if rule exists in chain
rule_exists() {
  local chain="$1"
  shift
  sudo iptables -C "$chain" "$@" 2>/dev/null
}

# Helper function: Add rule if not exists
add_rule_if_missing() {
  local chain="$1"
  shift
  if ! rule_exists "$chain" "$@"; then
    sudo iptables -A "$chain" "$@"
    echo "  [+] Added rule to $chain"
    return 0
  else
    echo "  [=] Rule already exists in $chain"
    return 1
  fi
}

# === Clean up existing custom chains ===
echo "[1/7] Setting up logging chains..."

# Helper function: Remove all references to a chain and delete it
cleanup_chain() {
  local chain="$1"
  if chain_exists "$chain"; then
    echo "  [~] Resetting $chain chain..."
    # Remove ALL references from INPUT chain
    while sudo iptables -D INPUT -j "$chain" 2>/dev/null; do :; done
    # Remove ALL references from DOCKER-USER chain
    while sudo iptables -D DOCKER-USER -j "$chain" 2>/dev/null; do :; done
    # Remove ALL references from other potential chains
    while sudo iptables -D FORWARD -j "$chain" 2>/dev/null; do :; done
    # Flush the chain
    sudo iptables -F "$chain" 2>/dev/null || true
    # Delete the chain
    sudo iptables -X "$chain" 2>/dev/null || true
  fi
}

# Remove existing logging chains
cleanup_chain "LOGGING-LOCAL"
cleanup_chain "LOGGING-DOCKER"

# Create fresh logging chains
echo "  [+] Creating LOGGING-LOCAL chain..."
if ! chain_exists "LOGGING-LOCAL"; then
  sudo iptables -N LOGGING-LOCAL
else
  echo "  [!] Warning: LOGGING-LOCAL still exists, flushing instead..."
  sudo iptables -F LOGGING-LOCAL
fi
sudo iptables -A LOGGING-LOCAL -j LOG \
  --log-prefix "FIREWALL-INPUT - RIP: " \
  --log-level 4
sudo iptables -A LOGGING-LOCAL -j DROP

echo "  [+] Creating LOGGING-DOCKER chain..."
if ! chain_exists "LOGGING-DOCKER"; then
  sudo iptables -N LOGGING-DOCKER
else
  echo "  [!] Warning: LOGGING-DOCKER still exists, flushing instead..."
  sudo iptables -F LOGGING-DOCKER
fi
sudo iptables -A LOGGING-DOCKER -j LOG \
  --log-prefix "FIREWALL-DOCKER - RIP: " \
  --log-level 4
sudo iptables -A LOGGING-DOCKER -j DROP

# === Configure INPUT chain ===
echo "[2/7] Configuring INPUT chain for local network ($LOCAL_NETWORK)..."

# Enable PING from local network
add_rule_if_missing INPUT -i $IF -s $LOCAL_NETWORK \
  -p icmp -m icmp --icmp-type 8 \
  -j ACCEPT || true

# === SSH Access ===
echo "[3/7] Configuring SSH access..."

if [ "$ALLOW_LOCAL_SSH_ACCESS" = "true" ]; then
  echo "  [*] Enabling SSH from local network ($LOCAL_NETWORK)..."

  # Remove any existing SSH DROP rules first
  while rule_exists INPUT -i $IF -m conntrack --ctstate RELATED,ESTABLISHED -p tcp -m tcp --dport 22 -j LOGGING-LOCAL 2>/dev/null; do
    sudo iptables -D INPUT -i $IF -m conntrack --ctstate RELATED,ESTABLISHED -p tcp -m tcp --dport 22 -j LOGGING-LOCAL
  done

  add_rule_if_missing INPUT -i $IF -s $LOCAL_NETWORK \
    -p tcp -m tcp --dport 22 \
    -j ACCEPT || true
else
  echo "  [*] Disabling SSH from local network..."

  # Remove any existing SSH ACCEPT rules
  while rule_exists INPUT -i $IF -s $LOCAL_NETWORK -p tcp -m tcp --dport 22 -j ACCEPT 2>/dev/null; do
    sudo iptables -D INPUT -i $IF -s $LOCAL_NETWORK -p tcp -m tcp --dport 22 -j ACCEPT
  done

  # Drop established SSH connections
  add_rule_if_missing INPUT -i $IF \
    -m conntrack --ctstate RELATED,ESTABLISHED \
    -p tcp -m tcp --dport 22 \
    -j LOGGING-LOCAL || true
fi

# === Allow established connections ===
echo "[4/7] Configuring connection tracking..."

add_rule_if_missing INPUT \
  -m conntrack --ctstate RELATED,ESTABLISHED \
  -j ACCEPT || true

# Block all other INPUT traffic from interface
# First remove any existing rules, then add fresh
while rule_exists INPUT -i $IF -j LOGGING-LOCAL 2>/dev/null; do
  sudo iptables -D INPUT -i $IF -j LOGGING-LOCAL
done
sudo iptables -A INPUT -i $IF -j LOGGING-LOCAL
echo "  [+] Added default DROP rule for INPUT"

# === Configure DOCKER-USER chain ===
echo "[5/7] Configuring DOCKER-USER chain..."

# Check if DOCKER-USER chain exists (Docker must be installed)
if ! chain_exists "DOCKER-USER"; then
  echo "  [!] DOCKER-USER chain not found. Is Docker installed?"
  echo "  [!] Skipping Docker firewall rules..."
else
  # Allow established and related traffic back to containers
  add_rule_if_missing DOCKER-USER \
    -m conntrack --ctstate RELATED,ESTABLISHED \
    -j ACCEPT || true

  # === Local services access ===
  echo "[6/7] Configuring local service access..."

  if [ "$ALLOW_LOCAL_SERVICES_ACCESS" = "true" ]; then
    echo "  [*] Enabling access from local network to docker services..."

    # DNS (UDP + TCP)
    add_rule_if_missing DOCKER-USER -i $IF -s $LOCAL_NETWORK \
      -p udp -m udp --dport 53 \
      -j ACCEPT || true
    add_rule_if_missing DOCKER-USER -i $IF -s $LOCAL_NETWORK \
      -p tcp -m tcp --dport 53 \
      -j ACCEPT || true

    # HTTP + HTTPS
    add_rule_if_missing DOCKER-USER -i $IF -s $LOCAL_NETWORK \
      -p tcp -m tcp --dport 80 \
      -j ACCEPT || true
    add_rule_if_missing DOCKER-USER -i $IF -s $LOCAL_NETWORK \
      -p tcp -m tcp --dport 443 \
      -j ACCEPT || true
  else
    echo "  [*] Local service access disabled, removing any existing rules..."
    # Remove existing local service rules if they exist
    sudo iptables -D DOCKER-USER -i $IF -s $LOCAL_NETWORK -p udp -m udp --dport 53 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -i $IF -s $LOCAL_NETWORK -p tcp -m tcp --dport 53 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -i $IF -s $LOCAL_NETWORK -p tcp -m tcp --dport 80 -j ACCEPT 2>/dev/null || true
    sudo iptables -D DOCKER-USER -i $IF -s $LOCAL_NETWORK -p tcp -m tcp --dport 443 -j ACCEPT 2>/dev/null || true
  fi

  # Block all other traffic from docker-user chain
  # Remove existing and re-add to ensure it's at the right position
  while rule_exists DOCKER-USER -i $IF -j LOGGING-DOCKER 2>/dev/null; do
    sudo iptables -D DOCKER-USER -i $IF -j LOGGING-DOCKER
  done
  sudo iptables -A DOCKER-USER -i $IF -j LOGGING-DOCKER
  echo "  [+] Added default DROP rule for DOCKER-USER"

  # Ensure RETURN rule is at the bottom
  echo "[7/7] Ensuring RETURN rule is at bottom of DOCKER-USER..."
  sudo iptables -D DOCKER-USER -j RETURN 2>/dev/null || true
  sudo iptables -A DOCKER-USER -j RETURN
  echo "  [+] RETURN rule repositioned"
fi

# === Save rules ===
echo ""
echo "[*] Saving firewall rules..."

# Create directory if it doesn't exist
sudo mkdir -p /etc/iptables

# Save rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

echo ""
echo "=============================================="
echo "   Firewall Configuration Complete!           "
echo "=============================================="
echo ""
echo "Rules have been saved to /etc/iptables/rules.v4"
echo "They will persist across reboots (if iptables-persistent is installed)."
