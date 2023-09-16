#!/bin/bash
required_hotspot_vars=(
    "HOTSPOT_SSID"
    "HOTSPOT_PASSWORD"
)

required_vars=(
    # Armbian configuration environment variables
    "IP_ADDRESS"
    "IP_GATEWAY"
    "DNS_SERVERS"
    "SUBNET_MASK"

    # Enable hotspot environment variables
    "ENABLE_HOTSPOT"

    # Zero Trust firewall environment variables
    "ALLOW_LOCAL_SSH_ACCESS"
    "ALLOW_LOCAL_SERVICES_ACCESS"

    # TLS certificates environment variables
    "TLS_CERTIFICATE_COUNTRY"
    "TLS_CERTIFICATE_STATE"
    "TLS_CERTIFICATE_LOCALITY"
    "TLS_CERTIFICATE_ORGANIZATION"

    # Docker containers environment variables
    "CLOUDFLARE_EMAIL"
    "CLOUDFLARE_API_KEY"
    "RESTIC_REPOSITORY"
    "AWS_DEFAULT_REGION"
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "TELEGRAM_BOT_TOKEN"
    "TELEGRAM_CHAT_ID"
    "TUNNEL_TOKEN"
    "DNS_DOMAIN"
    "DNS_EMAIL"
    "ZIGBEE2MQTT_DEVICE"
    "ZIGBEE2MQTT_GATEWAY_ID"
)

# Ensure .env file exists in directory "../"
if [ ! -f .env ]; then
    echo "[!] .env file not found, please create one by copying .env.example in this directory and fill in the required variables"
    exit
fi

# Ensure script is run as root
if [ "$EUID" -ne 0 ]
  then echo "[!] Please run as root"
  exit
fi

# Ask user confirmation before starting
read -p "[!] This script will configure Armbian to run the home automation system, are you sure? (y/n) " -n 1 -r

# If user confirms, continue
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo ""
else
    echo ""
    echo "[!] Aborting..."
    exit
fi

# Load .env file variables
set -a
source .env 
set +a

# Now, ensure that all variables are set
for var in "${required_vars[@]}"
do
    if [ -z "${!var}" ]; then
        echo "[!] $var is not set, please set it in .env file"
        exit
    fi
done

# If, $ENABLE_HOTSPOT is set to true, then check if all hotspot variables are set
if [ "$ENABLE_HOTSPOT" = true ]; then
    for var in "${required_hotspot_vars[@]}"
    do
        if [ -z "${!var}" ]; then
            echo "[!] $var is not set, please set it in .env file"
            exit
        fi
    done
fi

# Setup OS - steps:
# 1 - Update and upgrade the system
# 2 - Install requirements
# 3 - Start required services
# 4 - Setup system services
# 5 - Setup static IP address
# 6 - Setup wifi hotspot (optional)
# 7 - Overwrite NTP server (if the only DNS is the machine itself)
echo "[*] Setting up operating system..."
sudo bash ./scripts/os/setup-os.sh

# Check if error occurred
if [ $? -ne 0 ]; then
    echo "[!] An error occurred while setting up Armbian OS, aborting..."
    exit
else
    echo "[OK] Operating system setup completed successfully"
fi

# Create .tmp directory
mkdir -p ./.tmp || true

# Setup Docker containers networks, volumes and configuration files
containers_scripts=$(find ./scripts/containers -name "setup-*.sh" -o -name "post-setup-*.sh" | sort -r)
for script in $containers_scripts
do
    # Compute short name
    short_name=$(basename $script | cut -d- -f2 | cut -d. -f1)
    # Print container name in uppercase
    echo "[*] Configuring $short_name..."
    # Execute script
    sudo bash $script
    # Check if error occurred
    if [ $? -ne 0 ]; then
        echo "[!] An error occurred while configuring $short_name, aborting..."
        exit
    else
        echo "[OK] $short_name configured successfully"
    fi
done

# Remove .tmp directory
rm -rf ./.tmp

# Setting up firewall rules
echo "[*] Setting up Zero Trust firewall rules..."
sudo bash ./scripts/firewall/zero-trust-firewall.sh

# Check if error occurred
if [ $? -ne 0 ]; then
    echo "[!] An error occurred while setting up Zero Trust firewall rules, aborting..."
    exit
else
    echo "[OK] Zero Trust firewall rules configured successfully"
fi

# System hardening - steps:
echo "[*] Hardening system..."
sudo bash ./scripts/system-hardening/system-hardening.sh

# Check if error occurred
if [ $? -ne 0 ]; then
    echo "[!] An error occurred while hardening the system, aborting..."
    exit
else
    echo "[OK] System hardened successfully"
fi

# Notify user that the next step could interrupt the SSH connection
echo "[!] The next step will update the network settings. If you are connected via SSH, you will be disconnected. These are the new network settings:"
echo "----------------------------------"
echo "Ethernet configuration: "
echo "- IP Address: $IP_ADDRESS/$SUBNET_MASK"
echo "- Gateway: $IP_GATEWAY"
echo "- DNS Servers: $DNS_SERVERS"
echo "----------------------------------"
echo "Hotspot enabled? $ENABLE_HOTSPOT"
echo "- SSID: $HOTSPOT_SSID"
echo "- Password: $HOTSPOT_PASSWORD"
echo "----------------------------------"
echo ""
echo "WARNING: the system will reboot after applying the new network settings. If the ip address changes, you will need to reconnect via SSH using the new IP address."
echo ""

# Ask user confirmation before starting
read -p "[!] Are you sure you want to continue? (y/n) " -n 1 -r

# If user confirms, continue
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo ""
else
    echo ""
    echo "[!] Aborting..."
    exit
fi

# Setup network settings
echo "[*] Applying network settings..."
sudo bash ./scripts/armbian/setup-network.sh

# Check if error occurred
if [ $? -ne 0 ]; then
    echo "[!] An error occurred while setting up network settings, aborting..."
    exit
else
    echo "[OK] Network settings applied successfully"
fi

# Notify success
echo "----------------------------------------------"
echo "----    OS setup completed successfully   ----"
echo "----------------------------------------------"

# Reboot system
reboot
