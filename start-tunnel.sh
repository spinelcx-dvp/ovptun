#!/bin/bash
set -e

CF_VERSION="2024.10.0"
CF_URL="https://github.com/cloudflare/cloudflared/releases/download/${CF_VERSION}/cloudflared-linux-amd64"

echo "▶ Downloading cloudflared version ${CF_VERSION}..."

download_ok=0
for attempt in 1 2 3; do
  echo "  Attempt $attempt..."
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
  echo "❌ Failed to download cloudflared after 3 attempts"
  exit 1
fi

# بررسی سلامت فایل
if ! file /tmp/cloudflared | grep -q "ELF 64-bit"; then
  echo "❌ Downloaded file is not a valid ELF binary"
  ls -la /tmp/cloudflared
  file /tmp/cloudflared || true
  exit 1
fi

chmod +x /tmp/cloudflared

echo "▶ Cloudflared version:"
/tmp/cloudflared --version || true

echo "▶ Starting TCP tunnel to OpenVPN..."
nohup /tmp/cloudflared tunnel --url tcp://localhost:443 --no-autoupdate > /tmp/cloudflared.log 2>&1 &

echo "▶ Waiting for tunnel URL..."
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
  echo "❌ Failed to get tunnel URL after 90 seconds"
  echo "--- cloudflared log ---"
  cat /tmp/cloudflared.log
  exit 1
fi

echo "$TUNNEL_HOST" > /tmp/tunnel_host.txt
echo "✅ OpenVPN tunnel ready: $TUNNEL_HOST:443"
