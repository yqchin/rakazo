#!/data/data/com.termux/files/usr/bin/bash
# Run in Termux on an always-on Android phone at home. Keeps a tunnel open to the Hermes server so
# Hermes's browser reaches websites through this phone's internet (home Wi-Fi, or mobile data when
# Wi-Fi is down). Reconnects by itself after drops. Usage: bash phone-tunnel.sh <server-ip>
SERVER="${1:?usage: bash phone-tunnel.sh <server-ip>}"
termux-wake-lock 2>/dev/null || true
while true; do
  ssh -N -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=accept-new -R 172.17.0.1:1080 "root@$SERVER"
  echo "$(date) tunnel closed, reconnecting in 15 seconds"
  sleep 15
done
