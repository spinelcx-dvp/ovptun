#!/bin/bash
set -e

CHISEL_VERSION="v1.9.1"
CHISEL_URL="https://github.com/jpillora/chisel/releases/download/${CHISEL_VERSION}/chisel_1.9.1_linux_amd64.gz"

echo "▶ Downloading chisel ${CHISEL_VERSION}..."
download_ok=0
for attempt in 1 2 3; do
  echo "  Attempt $attempt..."
  if wget --timeout=30 --tries=2 -q "$CHISEL_URL" -O /tmp/chisel.gz; then
    download_ok=1
    break
  fi
  sleep 3
done

if [ "$download_ok" -ne 1 ]; then
  echo "❌ Failed to download chisel after 3 attempts"
  exit 1
fi

gunzip -f /tmp/chisel.gz
mv /tmp/chisel /tmp/chisel-bin
chmod +x /tmp/chisel-bin

echo "▶ Chisel version:"
/tmp/chisel-bin --version || true

echo "▶ Starting chisel server on port 8080..."
# chisel server را روی پورت محلی 8080 راه‌اندازی می‌کنیم
# cloudflared ترافیک WebSocket را به این پورت می‌فرستد
# و chisel آن را به OpenVPN (localhost:443) فوروارد می‌کند
nohup /tmp/chisel-bin server --port 8080 --socks5 443 --proxy http://localhost:8080 > /tmp/chisel.log 2>&1 &

sleep 3
if ! pgrep -f "chisel-bin server" > /dev/null; then
  echo "❌ Chisel server failed to start"
  cat /tmp/chisel.log
  exit 1
fi
echo "✅ Chisel server is running on port 8080"

echo "▶ Downloading cloudflared..."
CF_VERSION="2024.10.0"
CF_URL="https://github.com/cloudflare/cloudflared/releases/download/${CF_VERSION}/cloudflared-linux-amd64"

download_ok=0
for attempt in 1 2 3; do
  if wget --timeout=30 --tries=2 -q "$CF_URL" -O /tmp/cloudflared; then
    download_ok=1
    break
  fi
  if curl -fsSL --max-time 60 "$CF_URL" -o /tmp/cloudflared; then
    download_ok=1
    break
  fi
  sleep 3
done

if [ "$download_ok" -ne 1 ]; then
  echo "❌ Failed to download cloudflared"
  exit 1
fi

if ! file /tmp/cloudflared | grep -q "ELF 64-bit"; then
  echo "❌ Downloaded cloudflared is not a valid ELF binary"
  exit 1
fi

chmod +x /tmp/cloudflared

echo "▶ Starting cloudflared tunnel to chisel (http://localhost:8080)..."
nohup /tmp/cloudflared tunnel --url http://localhost:8080 --no-autoupdate > /tmp/cloudflared.log 2>&1 &

TUNNEL_HOST=""
for i in {1..45}; do
  if grep -q "trycloudflare.com" /tmp/cloudflared.log 2>/dev/null; then
    TUNNEL_HOST=$(grep -o '[a-zA-Z0-9.-]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
    break
  fi
  if ! pgrep -f "cloudflared tunnel" > /dev/null; then
    echo "❌ Cloudflared process died"
    cat /tmp/cloudflared.log
    exit 1
  fi
  sleep 2
done

if [ -z "$TUNNEL_HOST" ]; then
  echo "❌ Failed to get tunnel URL"
  cat /tmp/cloudflared.log
  exit 1
fi

echo "$TUNNEL_HOST" > /tmp/tunnel_host.txt
echo "✅ Chisel tunnel ready: $TUNNEL_HOST"
