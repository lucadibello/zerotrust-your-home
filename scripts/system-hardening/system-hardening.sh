#!/bin/bash

# System Hardening

## 1) Authentication and password policies
echo "[*] Setting authentication and password policies"

# Set password hashing rounds
echo "SHA_CRYPT_MIN_ROUNDS 10000" | sudo tee -a /etc/login.defs

# Configure pam_passwdqc module to enforce strong passwords
sudo sed -i '/pam_passwdqc.so/ s/$/ retry=3 enforce=everyone min=disabled,14,14,14,14 max=40/' /etc/pam.d/common-password

# Set minimum password age to 1 day
sudo sed -i '/PASS_MIN_DAYS/ s/0/1/' /etc/login.defs

# Set maximum password age to 90 days
sudo sed -i '/PASS_MAX_DAYS/ s/99999/90/' /etc/login.defs

## 2) Change default UMASK permissions
echo "[*] Changing default UMASK permissions"

sudo sed -i '/UMASK/ s/022/027/' /etc/login.defs


## 3) Purging unnecessary packages
echo "[*] Purging unnecessary packages"

sudo apt purge -y

## 4) Disable unused kernel modules
echo "[*] Disabling unused kernel modules"

modules=(
  "dccp"
  "sctp"
  "rds"
  "tipc"
)

# Disable kernel modules
for module in "${modules[@]}"; do
  echo "install $module /bin/true" | sudo tee -a /etc/modprobe.d/$module.conf
  echo "blacklist $module" | sudo tee -a /etc/modprobe.d/$module.conf
done

## 5) SSH service hardening
echo "[*] SSH service hardening"

echo "AllowTcpForwarding no" | sudo tee -a /etc/ssh/ssh_config
echo "ClientAliveCountMax 2" | sudo tee -a /etc/ssh/sshd_config
echo "LogLevel VERBOSE" | sudo tee -a /etc/ssh/sshd_config
echo "MaxAuthTries 3" | sudo tee -a /etc/ssh/sshd_config
echo "MaxSessions 2" | sudo tee -a /etc/ssh/sshd_config
echo "PermitRootLogin no" | sudo tee -a /etc/ssh/sshd_config
echo "TCPKeepAlive no" | sudo tee -a /etc/ssh/sshd_config
echo "X11Forwarding no" | sudo tee -a /etc/ssh/sshd_config
echo "AllowAgentForwarding no" | sudo tee -a /etc/ssh/sshd_config
sudo service ssh restart

## 6) Legal notice banner
echo "[*] Adding legal notice banner"

echo "This system is private. Unauthorized access is prohibited." | sudo tee /etc/issue
echo "This system is private. Unauthorized access is prohibited." | sudo tee /etc/issue.net
echo "Banner /etc/issue.net" | sudo tee -a /etc/ssh/sshd_config
sudo service sshd restart

## 7) System auditing
echo "[*] Installing system auditing tools"

sudo apt install auditd -y
sudo wget -P /etc/audit/audit.d https://raw.githubusercontent.com/Neo23x0/auditd/master/audit.rules -O audit.rules
sudo service auditd restart

## 8) Kernel hardening
echo "[*] Kernel hardening"

# Backup current kernel configuration
sudo sysctl -a > /tmp/sysctl-defaults.conf

# Write changes in new file
echo "kernel.dmesg_restrict = 1" | sudo tee -a /etc/sysctl.d/80-lynis.conf
echo "kernel.sysrq = 0" | sudo tee -a /etc/sysctl.d/80-lynis.conf
echo "net.ipv4.conf.all.accept_redirects = 0" | sudo tee -a /etc/sysctl.d/80-lynis.conf
echo "net.ipv4.conf.all.log_martians = 1" | sudo tee -a /etc/sysctl.d/80-lynis.conf
echo "net.ipv4.conf.all.send_redirects = 0" | sudo tee -a /etc/sysctl.d/80-lynis.conf
echo "net.ipv4.conf.default.accept_redirects = 0" | sudo tee -a /etc/sysctl.d/80-lynis.conf
echo "net.ipv4.conf.default.log_martians = 1" | sudo tee -a /etc/sysctl.d/80-lynis.conf

# Apply changes
sudo sysctl --system

## 9) Restrict compilers to root users
echo "[*] Restricting compilers to root users only"

# Look for compilers executables in the system
compilers=$(find / -type f \( -name "gcc*" -o -name "g++*" -o -name "cc*" -o -name "c++*" \) -executable)

# Restrict access to compilers
for compiler in $compilers; do
  echo "- Restricting access to $compiler"
  sudo chmod o-rx $compiler
done