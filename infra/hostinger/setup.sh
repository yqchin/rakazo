#!/bin/bash
# Installs Rakazo (published images), Docker computers and HTTPS on a fresh Ubuntu 24.04 VPS.
# Usage (as root): bash setup.sh   Set RAKAZO_PUBLIC_HOST=app.example.com to use your own domain;
# otherwise the server gets a free <ip>.sslip.io address.
# Progress: /root/rakazo-setup.log. Finished marker: /root/RAKAZO_READY (or /root/RAKAZO_FAILED).
set -euo pipefail
exec > >(tee -a /root/rakazo-setup.log) 2>&1
trap 'echo "SETUP FAILED at line $LINENO"; date > /root/RAKAZO_FAILED' ERR

IP=$(curl -4 -fsS https://api.ipify.org || hostname -I | awk "{print \$1}")
HOST="${RAKAZO_PUBLIC_HOST:-$(echo "$IP" | tr . -).sslip.io}"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
APT="apt-get -o DPkg::Lock::Timeout=900 -y"
echo "== $(date) starting Rakazo setup for $HOST"

# 4 GB swap as a safety net for the 8 GB server.
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

$APT update
$APT upgrade
$APT install curl ca-certificates openssl caddy unattended-upgrades

command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

mkdir -p /opt/rakazo && cd /opt/rakazo
curl -fsSLO https://raw.githubusercontent.com/elie222/rakazo/main/infra/compose/install-images.sh
bash install-images.sh --prepare-only
sed -i -E "s#^(BETTER_AUTH_URL|WEB_ORIGIN|API_URL)=.*#\1=https://$HOST#; s#^RAKAZO_HOST=.*#RAKAZO_HOST=$HOST#" .env
bash install-images.sh

printf '%s {\n\treverse_proxy 127.0.0.1:5173\n}\n' "$HOST" > /etc/caddy/Caddyfile
systemctl enable caddy
systemctl restart caddy

echo "== $(date) DONE. Open https://$HOST"
date > /root/RAKAZO_READY
