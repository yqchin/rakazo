#!/bin/sh
# Opens the Hermes bot's browser profile WITHOUT Hermes's remote control, so a person can sign in
# to sites that refuse automated browsers (for example Google). Run it in the Bot Screen's terminal:
#   sh /opt/data/manual-chrome.sh
# Sign in, close the window completely, then hand control back; the bot reuses the saved login.
B=$(hermes config get browser.executable_path 2>/dev/null | tail -n1)
[ -x "$B" ] || B=$(cat /etc/hermes/chromium-executable-path)
P=$(hermes config get browser.user_data_dir 2>/dev/null | tail -n1)
[ -d "$P" ] || P=/opt/data/bot-desktop/browser-profile

if [ -L "$P/SingletonLock" ] || [ -e "$P/SingletonLock" ]; then
  echo "The bot's browser is still open. Close its window first, then run this again."
  exit 1
fi

echo "Browser: $B"
echo "Profile: $P"
echo "Opening without remote control. Sign in, then close the window completely."
exec "$B" --user-data-dir="$P" --no-sandbox --no-first-run
