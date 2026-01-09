#!/bin/bash

# System Hardening Script (Idempotent)
# This script can be safely re-run on existing instances to update security settings.

set -e

# Helper function: Add line to file if not already present
add_line_if_missing() {
  local file="$1"
  local line="$2"
  if ! grep -qF "$line" "$file" 2>/dev/null; then
    echo "$line" | sudo tee -a "$file" > /dev/null
    echo "  [+] Added: $line"
    return 0
  else
    echo "  [=] Already present: $line"
    return 1
  fi
}

# Helper function: Set config value (replace or add)
set_config_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local delimiter="${4:- }"  # Default delimiter is space

  if grep -q "^${key}${delimiter}" "$file" 2>/dev/null; then
    # Key exists, update value
    sudo sed -i "s|^${key}${delimiter}.*|${key}${delimiter}${value}|" "$file"
    echo "  [~] Updated: ${key}${delimiter}${value}"
  elif grep -q "^#.*${key}${delimiter}" "$file" 2>/dev/null; then
    # Key exists but commented, uncomment and set
    sudo sed -i "s|^#.*${key}${delimiter}.*|${key}${delimiter}${value}|" "$file"
    echo "  [~] Uncommented and set: ${key}${delimiter}${value}"
  else
    # Key doesn't exist, add it
    echo "${key}${delimiter}${value}" | sudo tee -a "$file" > /dev/null
    echo "  [+] Added: ${key}${delimiter}${value}"
  fi
}

echo "=============================================="
echo "     System Hardening Script (Idempotent)     "
echo "=============================================="
echo ""

## 1) Authentication and password policies
echo "[1/9] Setting authentication and password policies..."

# Set password hashing rounds
if ! grep -q "^SHA_CRYPT_MIN_ROUNDS" /etc/login.defs 2>/dev/null; then
  add_line_if_missing /etc/login.defs "SHA_CRYPT_MIN_ROUNDS 10000"
else
  set_config_value /etc/login.defs "SHA_CRYPT_MIN_ROUNDS" "10000"
fi

# Set minimum password age to 1 day
if grep -q "^PASS_MIN_DAYS" /etc/login.defs; then
  current_val=$(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
  if [ "$current_val" != "1" ]; then
    sudo sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t1/' /etc/login.defs
    echo "  [~] Updated PASS_MIN_DAYS to 1"
  else
    echo "  [=] PASS_MIN_DAYS already set to 1"
  fi
fi

# Set maximum password age to 90 days
if grep -q "^PASS_MAX_DAYS" /etc/login.defs; then
  current_val=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
  if [ "$current_val" != "90" ]; then
    sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/' /etc/login.defs
    echo "  [~] Updated PASS_MAX_DAYS to 90"
  else
    echo "  [=] PASS_MAX_DAYS already set to 90"
  fi
fi

# Configure pam_passwdqc module (only if not already configured)
if grep -q "pam_passwdqc.so" /etc/pam.d/common-password 2>/dev/null; then
  if ! grep -q "pam_passwdqc.so.*retry=3" /etc/pam.d/common-password; then
    sudo sed -i '/pam_passwdqc.so/ s/$/ retry=3 enforce=everyone min=disabled,14,14,14,14 max=40/' /etc/pam.d/common-password
    echo "  [~] Updated pam_passwdqc settings"
  else
    echo "  [=] pam_passwdqc already configured"
  fi
fi

## 2) Change default UMASK permissions
echo "[2/9] Changing default UMASK permissions..."

if grep -q "^UMASK" /etc/login.defs; then
  current_umask=$(grep "^UMASK" /etc/login.defs | awk '{print $2}')
  if [ "$current_umask" != "027" ]; then
    sudo sed -i 's/^UMASK.*/UMASK\t\t027/' /etc/login.defs
    echo "  [~] Updated UMASK to 027"
  else
    echo "  [=] UMASK already set to 027"
  fi
fi

## 3) Purging unnecessary packages
echo "[3/9] Checking for unnecessary packages..."
# Note: apt purge -y without packages does nothing harmful
sudo apt purge -y 2>/dev/null || true
echo "  [=] Package cleanup complete"

## 4) Disable unused kernel modules
echo "[4/9] Disabling unused kernel modules..."

modules=(
  "dccp"
  "sctp"
  "rds"
  "tipc"
)

for module in "${modules[@]}"; do
  conf_file="/etc/modprobe.d/${module}.conf"
  needs_update=false

  if [ ! -f "$conf_file" ]; then
    needs_update=true
  else
    if ! grep -q "install $module /bin/true" "$conf_file" 2>/dev/null; then
      needs_update=true
    fi
    if ! grep -q "blacklist $module" "$conf_file" 2>/dev/null; then
      needs_update=true
    fi
  fi

  if [ "$needs_update" = true ]; then
    # Overwrite the file with correct content (idempotent)
    echo "install $module /bin/true" | sudo tee "$conf_file" > /dev/null
    echo "blacklist $module" | sudo tee -a "$conf_file" > /dev/null
    echo "  [+] Configured module blacklist: $module"
  else
    echo "  [=] Module already blacklisted: $module"
  fi
done

## 5) SSH service hardening
echo "[5/9] Hardening SSH service..."

# SSH client config - disable forwarding on client side
# Note: AllowTcpForwarding is a server-side option (sshd_config), not client-side

# SSH server config - use set_config_value for idempotency
sshd_settings=(
  "ClientAliveCountMax:2"
  "LogLevel:VERBOSE"
  "MaxAuthTries:3"
  "MaxSessions:2"
  "PermitRootLogin:no"
  "TCPKeepAlive:no"
  "X11Forwarding:no"
  "AllowAgentForwarding:no"
  "AllowTcpForwarding:no"
)

for setting in "${sshd_settings[@]}"; do
  key="${setting%%:*}"
  value="${setting##*:}"
  set_config_value /etc/ssh/sshd_config "$key" "$value"
done

echo "  [*] Restarting SSH service..."
sudo service ssh restart 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true

## 6) Legal notice banner
echo "[6/9] Configuring legal notice banner..."

banner_text="This system is private. Unauthorized access is prohibited."

# Set issue files (overwrite is fine - idempotent)
echo "$banner_text" | sudo tee /etc/issue > /dev/null
echo "$banner_text" | sudo tee /etc/issue.net > /dev/null
echo "  [=] Banner files updated"

# Add Banner config to sshd
set_config_value /etc/ssh/sshd_config "Banner" "/etc/issue.net"

echo "  [*] Restarting SSHD service..."
sudo service sshd restart 2>/dev/null || sudo systemctl restart ssh 2>/dev/null || true

## 7) System auditing
echo "[7/9] Configuring system auditing..."

# Install auditd if not present
if ! command -v auditd &> /dev/null; then
  echo "  [+] Installing auditd..."
  sudo apt install auditd -y
else
  echo "  [=] auditd already installed"
fi

# Download audit rules if not present or update them
audit_rules_file="/etc/audit/rules.d/audit.rules"
audit_rules_url="https://raw.githubusercontent.com/Neo23x0/auditd/master/audit.rules"

sudo mkdir -p /etc/audit/rules.d

# Download to temp file and compare with existing
temp_rules=$(mktemp)
download_success=false

if wget -q "$audit_rules_url" -O "$temp_rules" 2>/dev/null; then
  download_success=true
elif curl -sL "$audit_rules_url" -o "$temp_rules" 2>/dev/null; then
  download_success=true
fi

if [ "$download_success" = true ] && [ -s "$temp_rules" ]; then
  # Check if rules have changed
  if [ -f "$audit_rules_file" ] && [ -s "$audit_rules_file" ]; then
    old_hash=$(md5sum "$audit_rules_file" 2>/dev/null | cut -d' ' -f1)
    new_hash=$(md5sum "$temp_rules" 2>/dev/null | cut -d' ' -f1)

    if [ "$old_hash" = "$new_hash" ]; then
      echo "  [=] Audit rules are up to date"
      rm -f "$temp_rules"
    else
      echo "  [+] Audit rules have changed, updating..."
      sudo mv "$temp_rules" "$audit_rules_file"
      sudo chmod 640 "$audit_rules_file"
    fi
  else
    echo "  [+] Installing audit rules..."
    sudo mv "$temp_rules" "$audit_rules_file"
    sudo chmod 640 "$audit_rules_file"
  fi
else
  echo "  [!] Warning: Could not download audit rules"
  rm -f "$temp_rules"
fi

# Load and apply audit rules
if [ -s "$audit_rules_file" ]; then
  echo "  [*] Loading audit rules..."
  sudo augenrules --load 2>/dev/null || sudo auditctl -R "$audit_rules_file" 2>/dev/null || true
  sudo service auditd restart 2>/dev/null || sudo systemctl restart auditd 2>/dev/null || true

  # Verify rules were loaded
  rule_count=$(sudo auditctl -l 2>/dev/null | grep -c "^-" || echo "0")
  echo "  [=] Loaded $rule_count audit rules"
else
  echo "  [!] Warning: Audit rules file is empty or missing"
fi

## 8) Kernel hardening
echo "[8/9] Applying kernel hardening..."

sysctl_file="/etc/sysctl.d/80-lynis.conf"
sysctl_settings=(
  "kernel.dmesg_restrict = 1"
  "kernel.sysrq = 0"
  "net.ipv4.conf.all.accept_redirects = 0"
  "net.ipv4.conf.all.log_martians = 1"
  "net.ipv4.conf.all.send_redirects = 0"
  "net.ipv4.conf.default.accept_redirects = 0"
  "net.ipv4.conf.default.log_martians = 1"
)

# Create or update sysctl config (overwrite for idempotency)
echo "# Kernel hardening settings (managed by zerotrust-your-home)" | sudo tee "$sysctl_file" > /dev/null
echo "# Last updated: $(date)" | sudo tee -a "$sysctl_file" > /dev/null
echo "" | sudo tee -a "$sysctl_file" > /dev/null

for setting in "${sysctl_settings[@]}"; do
  echo "$setting" | sudo tee -a "$sysctl_file" > /dev/null
  echo "  [=] Set: $setting"
done

# Apply changes
echo "  [*] Applying sysctl settings..."
sudo sysctl --system > /dev/null 2>&1

## 9) Restrict compilers to root users
echo "[9/9] Restricting compiler access..."

# Find compilers and restrict access
compilers=$(find /usr -type f \( -name "gcc*" -o -name "g++*" -o -name "cc" -o -name "c++" \) -executable 2>/dev/null || true)

restricted_count=0
for compiler in $compilers; do
  # Check current permissions
  current_perms=$(stat -c "%a" "$compiler" 2>/dev/null || echo "000")
  # Check if 'others' have read or execute
  others_perms=$((current_perms % 10))
  if [ "$others_perms" -gt 0 ]; then
    sudo chmod o-rx "$compiler"
    echo "  [~] Restricted: $compiler"
    ((restricted_count++)) || true
  fi
done

if [ "$restricted_count" -eq 0 ]; then
  echo "  [=] Compilers already restricted"
else
  echo "  [+] Restricted $restricted_count compiler(s)"
fi

echo ""
echo "=============================================="
echo "     System Hardening Complete!              "
echo "=============================================="
echo ""
echo "Note: Some changes may require a system reboot to take full effect."
echo "Run with --force-update to refresh external resources (e.g., audit rules)."
