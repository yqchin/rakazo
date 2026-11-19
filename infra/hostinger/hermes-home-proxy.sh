#!/bin/bash
# Lets Hermes's browser reach websites through a device at home (for example an old Android phone
# running infra/hostinger/phone-tunnel.sh), so sites see a home connection instead of this server.
# When the home tunnel is down, the browser falls back to this server's own connection.
# Usage (as root, after the phone has added its key): bash hermes-home-proxy.sh
set -euo pipefail
GW=172.17.0.1        # Docker's host address: reachable from the Hermes container, not from the internet
SOCKS_PORT=1080      # where the phone's tunnel opens its proxy on this server
PAC_PORT=8090        # where Hermes's browser reads its proxy rules

# Let a tunnel listen on the Docker host address, and notice dropped tunnels within ~90 seconds.
cat > /etc/ssh/sshd_config.d/hermes-home-proxy.conf <<EOF
GatewayPorts clientspecified
ClientAliveInterval 30
ClientAliveCountMax 3
EOF
systemctl restart ssh

# The phone's key (comment "hermes-phone") may only open the tunnel: no shell, no other ports.
if [ -f /root/.ssh/authorized_keys ]; then
  sed -i -E "/ hermes-phone\$/ { /^restrict/! s/^/restrict,port-forwarding,permitlisten=\"$GW:$SOCKS_PORT\" / }" \
    /root/.ssh/authorized_keys
fi

# Proxy rules for the browser: use the home tunnel, otherwise connect directly.
if ! grep -q "hermes-home-proxy" /etc/caddy/Caddyfile; then
  cat >> /etc/caddy/Caddyfile <<EOF

# hermes-home-proxy: proxy rules for Hermes's browser
http://$GW:$PAC_PORT {
	header Content-Type application/x-ns-proxy-autoconfig
	respond "function FindProxyForURL(url, host) { return 'SOCKS5 $GW:$SOCKS_PORT; DIRECT'; }"
}
EOF
fi
systemctl reload caddy

docker exec hermes hermes config set browser.cloud_provider local
docker exec hermes hermes config set browser.user_data_dir /opt/data/browser-profile
docker exec hermes hermes config set browser.chromium_args "[\"--proxy-pac-url=http://$GW:$PAC_PORT/\"]"
docker restart hermes
echo "DONE: Hermes's browser now uses the home tunnel when it is up, and this server otherwise."
