#!/bin/bash
# Installs Hermes Agent (Nous Research) with its Bot Screen (a desktop and browser you can watch
# and take over) and HTTPS on a fresh Ubuntu 24.04 VPS.
# Usage (as root): bash hermes-setup.sh   Set HERMES_PUBLIC_HOST=app.example.com to use your own
# domain; otherwise the server gets a free <ip>.sslip.io address.
# Progress: /root/hermes-setup.log. Finished marker: /root/HERMES_READY (or /root/HERMES_FAILED).
# The Webapp login is generated here and saved to /root/hermes-login.txt (root only).
set -euo pipefail
exec > >(tee -a /root/hermes-setup.log) 2>&1
trap 'echo "SETUP FAILED at line $LINENO"; date > /root/HERMES_FAILED' ERR

IP=$(curl -4 -fsS https://api.ipify.org || hostname -I | awk '{print $1}')
HOST="${HERMES_PUBLIC_HOST:-$(echo "$IP" | tr . -).sslip.io}"
DATA=/opt/hermes-data
IMAGE=nousresearch/hermes-agent:latest-desktop
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
APT="apt-get -o DPkg::Lock::Timeout=900 -y"
echo "== $(date) starting Hermes setup for $HOST"

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

mkdir -p "$DATA"
# Hermes reads config.yaml from its data directory; only the settings this setup needs.
if [ ! -f "$DATA/config.yaml" ]; then
  cat > "$DATA/config.yaml" <<EOF
webapp:
  enabled: true
  host: 0.0.0.0
  port: 9120
  public_url: "https://$HOST"

dashboard:
  trusted_proxies:
    - "172.17.0.1"

browser:
  headed: true

bot_desktop:
  auto_start: true
  idle_stop_minutes: 30
EOF
fi

# Webapp login, generated once and kept across re-runs.
if [ ! -f /root/hermes-login.txt ]; then
  umask 077
  {
    echo "HERMES_URL=https://$HOST"
    echo "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin"
    echo "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$(openssl rand -hex 16)"
    echo "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$(openssl rand -hex 32)"
  } > /root/hermes-login.txt
  umask 022
fi

docker pull "$IMAGE"
docker rm -f hermes >/dev/null 2>&1 || true
docker run -d --name hermes --restart unless-stopped \
  --shm-size=1g \
  -v "$DATA":/opt/data \
  -p 127.0.0.1:9120:9120 \
  --env-file <(grep '^HERMES_DASHBOARD_' /root/hermes-login.txt) \
  "$IMAGE" gateway run

printf '%s {\n\treverse_proxy 127.0.0.1:9120\n}\n' "$HOST" > /etc/caddy/Caddyfile
systemctl enable caddy
systemctl restart caddy

echo "== $(date) DONE. Open https://$HOST and sign in with the login in /root/hermes-login.txt"
date > /root/HERMES_READY
