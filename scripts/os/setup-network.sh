#!/bin/bash
trap "exit" INT

# Load .env file
if [ -f .env ]; then
  set -a
  source .env 
  set +a
elif [ -f ../.env ]; then
  set -a
  source ../.env
  set +a
fi

# Source common helpers if available
if [ -f ./scripts/common.sh ]; then
  source ./scripts/common.sh
fi

## --- CHECK NETWORKMANAGER AVAILABILITY
if ! command -v nmcli >/dev/null 2>&1; then
  echo "[!] NetworkManager (nmcli) is not installed or available."
  echo "[!] If running inside a Proxmox VM, static IP is typically managed via Proxmox VE / Cloud-Init (/etc/network/interfaces or netplan)."
  echo "[*] Skipping NetworkManager configuration."
  exit 0
fi

# Ensure NetworkManager service is active
sudo systemctl start NetworkManager 2>/dev/null || true

## --- SETUP WIFI HOTSPOT (OPTIONAL)
if [ "${ENABLE_HOTSPOT:-false}" = "true" ]; then
  # Find Wireless interface
  wifi_interface=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep -w "wifi$" | head -n1 | cut -d: -f1)
  
  if [ -n "$wifi_interface" ]; then
    echo "[*] Configuring Wi-Fi hotspot on interface: $wifi_interface..."
    nmcli device wifi hotspot ifname "$wifi_interface" con-name hotspot ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASSWORD"
    nmcli connection up hotspot || echo "[!] Warning: Could not activate hotspot connection."
  fi
fi


## --- SETUP STATIC IP ADDRESS
echo "[*] Setting up static IP address and DNS server (Ethernet)..."

# Identify target Ethernet interface
target_if="${IF:-}"
if [ -z "$target_if" ] || ! ip link show "$target_if" >/dev/null 2>&1; then
  # Auto-detect ethernet interface
  if command -v get_default_network_interface >/dev/null 2>&1; then
    target_if=$(get_default_network_interface)
  else
    target_if=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep -w "ethernet$" | head -n1 | cut -d: -f1)
  fi
fi

echo "[*] Target Ethernet interface: ${target_if:-unknown}"

# Find existing connection profile for this interface or any ethernet connection
eth_connection=""
if [ -n "$target_if" ]; then
  eth_connection=$(nmcli -t -f NAME,DEVICE,TYPE connection show 2>/dev/null | grep ":${target_if}:ethernet$" | head -n1 | cut -d: -f1)
fi
if [ -z "$eth_connection" ]; then
  eth_connection=$(nmcli -t -f NAME,DEVICE,TYPE connection show 2>/dev/null | grep ":ethernet$" | head -n1 | cut -d: -f1)
fi

if [ -n "$eth_connection" ]; then
  echo "[*] Modifying existing NetworkManager connection: '$eth_connection'..."
  sudo nmcli connection modify "$eth_connection" ipv4.method manual ipv4.addresses "$IP_ADDRESS/$SUBNET_MASK" ipv4.gateway "$IP_GATEWAY"
  sudo nmcli connection modify "$eth_connection" ipv4.dns "$DNS_SERVERS"
  sudo nmcli connection up "$eth_connection" || echo "[!] Warning: Could not re-activate connection '$eth_connection'."
elif [ -n "$target_if" ]; then
  echo "[*] Creating new NetworkManager connection for device '$target_if'..."
  sudo nmcli connection add type ethernet con-name "$target_if" ifname "$target_if" \
    ipv4.method manual ipv4.addresses "$IP_ADDRESS/$SUBNET_MASK" ipv4.gateway "$IP_GATEWAY" ipv4.dns "$DNS_SERVERS"
  sudo nmcli connection up "$target_if" || echo "[!] Warning: Could not activate new connection '$target_if'."
else
  echo "[!] Warning: No Ethernet interface or connection profile found. If on Proxmox, please configure IP in Proxmox Cloud-Init."
fi

echo "[OK] Network configuration step completed."

