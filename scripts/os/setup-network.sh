#!/bin/bash

# Load .env file
set -a
source .env 
set +a

## --- SETUP WIFI HOTSPOT (OPTIONAL)

# Check if variable ENABLE_HOTSPOT is set to true
if [ "$ENABLE_HOTSPOT" = true ] ; then
    echo "[*] Setting up wifi hotspot..."

    # Find Wireless interface
    wifi_interface=$(nmcli -t -f DEVICE,TYPE device | grep -w "wifi$" | cut -d: -f1)
    # Start hotspot on that interface 
    nmcli device wifi hotspot ifname "$wifi_interface" con-name hotspot ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASSWORD"
    # Apply settings
    nmcli connection up hotspot

else
    echo "[*] Skipping wifi hotspot setup..."
fi

## --- SETUP STATIC IP ADDRESS
echo "[*] Setting up static IP address and DNS server (Ethernet)..."

# Get Ethernet connection name
eth_connection=$(nmcli -t -f NAME,DEVICE,TYPE connection show | grep ethernet | cut -d: -f1)
# Set manual IPv4 ethernet address
sudo nmcli connection modify "$eth_connection" ipv4.method manual ipv4.addresses "$IP_ADDRESS/$SUBNET_MASK" ipv4.gateway "$IP_GATEWAY"
# Set DNS server
sudo nmcli connection modify "$eth_connection" ipv4.dns "$DNS_SERVERS"
# Apply settings
sudo nmcli connection up "$eth_connection"
