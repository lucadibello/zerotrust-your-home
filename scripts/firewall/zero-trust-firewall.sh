#!/bin/bash

# Load .env file
set -a
source .env 
set +a

# Print configuration and ask for confirmation
echo "[!] The next step will update the firewall settings. If you are connected via SSH, you may be disconnected (depending on your settings)."
echo "----------------------------------"
echo "Firewall onfiguration:"
echo "  - Local network: $LOCAL_NETWORK"
echo "  - Primary interface: $IF"
echo "  - Enable SSH from local network: $ALLOW_LOCAL_SSH_ACCESS"
echo "  - Enable service access from local network:  $ALLOW_LOCAL_SERVICES_ACCESS"
echo ""

# Ask user for confirmation
read -p "Do you wish to continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
  echo "Aborting..."
  exit 1
fi

echo "--- Starting firewall configuration ---"

# Logging chain creation
echo "[!] Creating logging chains..."

sudo iptables -N LOGGING-LOCAL
sudo iptables -A LOGGING-LOCAL -j LOG \
  --log-prefix "FIREWALL-INPUT - RIP: " \
  --log-level 4
sudo iptables -A LOGGING-LOCAL -j DROP
sudo iptables -N LOGGING-DOCKER
sudo iptables -A LOGGING-DOCKER -j LOG \
  --log-prefix  "FIREWALL-DOCKER - RIP: " \
  --log-level 4
sudo iptables -A LOGGING-DOCKER -j DROP

# Logging chain creation
echo "[!] Enabling ping from local network ($LOCAL_NETWORK)..."

# Enable PING from local network
sudo iptables -A INPUT -i $IF -s $LOCAL_NETWORK \
  -p icmp -m icmp --icmp-type 8 \
  -j ACCEPT

# If enabled, allow SSH from local network
if [ "$ALLOW_LOCAL_SSH_ACCESS" = true ] ; then
  echo "[!] Enabling SSH from local network ($LOCAL_NETWORK)..."
  sudo iptables -A INPUT -i $IF -s $LOCAL_NETWORK \
    -p tcp -m tcp --dport 22 \
    -j ACCEPT
else
  echo "[!] Disabling SSH from local network ($LOCAL_NETWORK) and quitting established connections..."
  # Drop established and related traffic to SSH
  sudo iptables -A INPUT -i $IF \
    -m conntrack --ctstate RELATED,ESTABLISHED \
    -p tcp -m tcp --dport 22 \
    -j LOGGING-LOCAL
fi

# Allow established and related traffic to go back to local network
echo "[!] Allowing established and related traffic to flow back to local machine..."
sudo iptables -A INPUT \
  -m conntrack --ctstate RELATED,ESTABLISHED \
  -j ACCEPT

# Do not accept any other traffic from local network
echo "[!] Blocking all other traffic from local network..."
sudo iptables -A INPUT -i $IF \
  -j LOGGING-LOCAL

# Allow established and related traffic to go back to their containers
echo "[!] Allowing established and related traffic to flow back to docker containers"
sudo iptables -A DOCKER-USER \
  -m conntrack --ctstate RELATED,ESTABLISHED \
  -j ACCEPT

# If enabled, allow access from local network to local machine services
if [ "$ALLOW_LOCAL_SERVICES_ACCESS" = true ] ; then
  echo "[!] Enabling access from local network ($LOCAL_NETWORK) to docker services..."
  # DNS (UDP + TCP)
  sudo iptables -A DOCKER-USER -i $IF -s $LOCAL_NETWORK \
    -p udp -m udp --dport 53 \
    -j ACCEPT
  sudo iptables -A DOCKER-USER -i $IF -s $LOCAL_NETWORK \
    -p tcp -m tcp --dport 53 \
    -j ACCEPT
  # HTTP + HTTPS
  sudo iptables -A DOCKER-USER -i $IF -s $LOCAL_NETWORK \
    -p tcp -m tcp --dport 80 \
    -j ACCEPT
  sudo iptables -A DOCKER-USER -i $IF -s $LOCAL_NETWORK \
    -p tcp -m tcp --dport 443 \
    -j ACCEPT
fi

# Do not accept any other traffic from docker-user chain
echo "[!] Blocking all other traffic from docker containers..."
sudo iptables -A DOCKER-USER -i $IF \
  -j LOGGING-DOCKER

# Move RETURN rule to the bottom
echo "[!] Moving NAT RETURN rule to the bottom..."
sudo iptables -D DOCKER-USER \
  -j RETURN
sudo iptables -A DOCKER-USER \
  -j RETURN