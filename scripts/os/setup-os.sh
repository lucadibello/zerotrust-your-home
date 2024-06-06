#!/bin/bash

## -- DOWNLOAD AND INSTALL UPDATES
echo "[*] Updating and upgrading the system..."

# Update the system and install updates
sudo apt update && sudo apt upgrade -y

## -- INSTALL REQUIREMENTS
echo "[*] Installing requirements..."

# Install:
# - make (to use project utility file)
# - apparmor (Docker requirement)
# - ntp server (system clock synchronization)
# - unattended-upgrades
# - Install iptables-persistent
# - Install docker and docker-compose
# - Install and configure pam_passwdqc module to enforce strong passwords
# - Install sqlite3 (required to provision uptime-kuma database)
sudo apt install make apparmor systemd-timesyncd \
	unattended-upgrades iptables-persistent docker.io \
	docker-compose libpam-passwdqc sqlite3 -y

## -- START REQUIRED SERVICES

# Enable unattended-upgrades
echo "[*] Starting unattended-upgrades service..."
sudo systemctl enable unattended-upgrades
sudo systemctl start unattended-upgrades

# Start + enable systemd-timesyncd service
echo "[*] Starting systemd-timesyncd service..."
sudo systemctl start systemd-timesyncd.service
sudo systemctl enable systemd-timesyncd.service

## -- ADDITIONAL SERVICE SETUPS

# Enable ntp synchronization
echo "[*] Setting up time synchronization..."
sudo timedatectl set-ntp true

## -- SETUP CORRECT UDP BUFFER SIZE
# NOTE: This is required for cloudflare tunnel to work properly
# Link: https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
sudo sysctl -w net.core.rmem_max=7500000
sudo sysctl -w net.core.wmem_max=7500000

