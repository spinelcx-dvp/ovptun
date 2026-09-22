#!/bin/bash
set -e

echo "▶ Downloading cloudflared..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /tmp/cloudflared
chmod +x /tmp/cloudflared

echo "▶ Starting TCP tunnel to OpenVPN..."
nohup /tmp/cloudflared tunnel --url tcp://localhost:443 --no-autoupdate > /tmp/cloudflared.log 2>&1 &

echo "▶ Waiting for tunnel URL..."
for i in {1..40}; do
  if grep -q "trycloudflare.com" /tmp/cloudflared.log 2>/dev/null; then
    break
  fi
  sleep 2
done

TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
TUNNEL_HOST=$(echo "$TUNNEL_URL" | sed 's|https://||')

if [ -z "$TUNNEL_HOST" ]; then
  echo "❌ Failed to get tunnel URL"
  cat /tmp/cloudflared.log
  exit 1
fi

echo "$TUNNEL_HOST" > /tmp/tunnel_host.txt
echo "✅ OpenVPN tunnel ready: $TUNNEL_HOST:443"
