#!/usr/bin/env bash
#
# install-fail2ban-en.sh - Install and configure basic fail2ban (SSH brute-force protection)
# Target: Debian/Ubuntu (APT based)
#

set -euo pipefail

echo "==== Fail2ban Install Wizard (hz-oneclick) ===="

if [[ $EUID -ne 0 ]]; then
  echo "Please run this script as root." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script only supports APT-based Debian/Ubuntu systems for now." >&2
  exit 1
fi

# Step 1: Install fail2ban
if command -v fail2ban-client >/dev/null 2>&1; then
  echo "[Step 1/3] fail2ban is already installed, skipping installation."
else
  echo "[Step 1/3] Installing fail2ban..."
  apt-get update -y
  apt-get install -y fail2ban
fi

# Step 2: Write basic jail config
CONF_DIR="/etc/fail2ban/jail.d"
CONF_FILE="${CONF_DIR}/hz-basic.conf"

echo "[Step 2/3] Writing basic config to ${CONF_FILE} ..."
mkdir -p "$CONF_DIR"

if [[ -f "$CONF_FILE" ]]; then
  cp "$CONF_FILE" "${CONF_FILE}.$(date +%Y%m%d%H%M%S).bak"
  echo "Existing config backed up to ${CONF_FILE}.$(date +%Y%m%d%H%M%S).bak"
fi

cat > "$CONF_FILE" <<'EOF'
# hz-oneclick: basic fail2ban configuration (you can adjust as needed)

[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

# Basic SSH brute-force protection
# If your SSH (port 22) is not exposed to the public internet, this jail
# will have limited impact but is generally safe to keep.
[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 5
EOF

# Step 3: Enable and start the service
echo "[Step 3/3] Enabling and starting fail2ban..."
systemctl enable --now fail2ban

echo
echo "==== Done: fail2ban installed with basic SSH protection enabled ===="
echo "You can check status with:"
echo "  fail2ban-client status"
echo "  fail2ban-client status sshd"
echo
echo "To add jails for OLS / Nginx / other services, edit:"
echo "  /etc/fail2ban/jail.d/hz-basic.conf"
echo
echo "Note: If you already keep SSH closed on the public internet and use"
echo "      solutions like Tailscale, fail2ban is mostly an extra safety net."
