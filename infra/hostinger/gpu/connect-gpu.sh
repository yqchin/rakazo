#!/bin/bash
# Runs ON the Hermes VPS. Sets up a fresh GPU instance with ltx-setup.sh, then keeps a private tunnel
# so Hermes reaches that GPU's ComfyUI at http://172.17.0.1:8188 (not reachable from the internet).
# Usage: bash connect-gpu.sh <gpu-host> [ssh-port] [user]   (asks for your Hugging Face token, hidden)
# A non-root user needs passwordless sudo on the GPU instance (the setup installs packages and a service).
set -euo pipefail
HOST="${1:?usage: bash connect-gpu.sh <gpu-host> [ssh-port] [user]}"
PORT="${2:-22}"
USER_NAME="${3:-root}"
KEY=/root/.ssh/gpu_key
SSH=(ssh -i "$KEY" -p "$PORT" -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 "$USER_NAME@$HOST")
SRC=https://raw.githubusercontent.com/yqchin/rakazo/main/infra/hostinger/gpu/ltx-setup.sh

read -rsp "Hugging Face token (hidden): " HF; echo
SUDO=""; [ "$USER_NAME" = root ] || SUDO="sudo -n"
curl -fsSL "$SRC" | "${SSH[@]}" 'cat > /tmp/ltx-setup.sh'
printf '%s\n' "$HF" | "${SSH[@]}" "$SUDO bash /tmp/ltx-setup.sh"
unset HF

cat > /etc/systemd/system/gpu-tunnel.service <<UNIT
[Unit]
Description=Private tunnel to the GPU instance's ComfyUI
After=network-online.target docker.service

[Service]
ExecStart=/usr/bin/ssh -N -i $KEY -p $PORT -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -L 172.17.0.1:8188:127.0.0.1:8188 $USER_NAME@$HOST
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable gpu-tunnel
systemctl restart gpu-tunnel
sleep 5
curl -fs http://172.17.0.1:8188/system_stats >/dev/null && echo "DONE: Hermes can reach ComfyUI at http://172.17.0.1:8188" || echo "Tunnel not up yet: check with: systemctl status gpu-tunnel"
