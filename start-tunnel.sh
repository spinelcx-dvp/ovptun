#!/bin/bash
set -e

echo "▶ Cleaning up previous build directory..."
sudo rm -rf /tmp/openvpn-build 2>/dev/null || true
sudo rm -rf /tmp/chisel* 2>/dev/null || true
sudo rm -rf /tmp/cloudflared* 2>/dev/null || true

echo "═══════════════════════════════════════"
echo "▶ Step 1: Downloading chisel..."
echo "═══════════════════════════════════════"

CHISEL_URL="https://github.com/jpillora/chisel/releases/download/v1.9.1/chisel_1.9.1_linux_amd64.gz"

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
  echo "❌ Failed to download chisel"
  exit 1
fi

gunzip -f /tmp/chisel.gz
mv /tmp/chisel /tmp/chisel-bin
chmod +x /tmp/chisel-bin

if ! file /tmp/chisel-bin | grep -q "ELF 64-bit"; then
  echo "❌ chisel is not a valid ELF binary"
  exit 1
fi

echo "  chisel version: $(/tmp/chisel-bin --version 2>&1 | head -1)"

echo ""
echo "═══════════════════════════════════════"
echo "▶ Step 2: Starting chisel server on 8080"
echo "═══════════════════════════════════════"

nohup /tmp/chisel-bin server \
  --port 8080 \
  --backend http://localhost:443 \
  --keepalive 25s \
  > /tmp/chisel.log 2>&1 &

sleep 4

if ! pgrep -f "chisel-bin server" > /dev/null; then
  echo "❌ Chisel server failed to start"
  cat /tmp/chisel.log
  exit 1
fi

echo "✅ Chisel server running"

echo ""
echo "═══════════════════════════════════════"
echo "▶ Step 3: Downloading cloudflared"
echo "═══════════════════════════════════════"

CF_VERSION="2024.10.0"
CF_URL="https://github.com/cloudflare/cloudflared/releases/download/${CF_VERSION}/cloudflared-linux-amd64"

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
  echo "❌ Failed to download cloudflared"
  exit 1
fi

if ! file /tmp/cloudflared | grep -q "ELF 64-bit"; then
  echo "❌ cloudflared is not a valid ELF binary"
  exit 1
fi

chmod +x /tmp/cloudflared

echo ""
echo "═══════════════════════════════════════"
echo "▶ Step 4: Starting cloudflared tunnel (http2 protocol)"
echo "═══════════════════════════════════════"

nohup /tmp/cloudflared tunnel --url http://localhost:8080 --protocol http2 --no-autoupdate > /tmp/cloudflared.log 2>&1 &

TUNNEL_HOST=""
for i in {1..90}; do
  if grep -q "trycloudflare.com" /tmp/cloudflared.log 2>/dev/null; then
    TUNNEL_HOST=$(grep -o '[a-zA-Z0-9.-]*\.trycloudflare\.com' /tmp/cloudflared.log | head -1)
    break
  fi
  if ! pgrep -f "cloudflared tunnel" > /dev/null; then
    echo "❌ Cloudflared process died"
    echo "--- cloudflared.log ---"
    cat /tmp/cloudflared.log
    exit 1
  fi
  if [ $((i % 15)) -eq 0 ]; then
    echo "  waited $((i*2))s... last log line:"
    tail -1 /tmp/cloudflared.log
  fi
  sleep 2
done

if [ -z "$TUNNEL_HOST" ]; then
  echo "❌ Failed to get tunnel URL after 180s"
  echo "--- cloudflared.log ---"
  cat /tmp/cloudflared.log
  exit 1
fi

echo "$TUNNEL_HOST" > /tmp/tunnel_host.txt
echo ""
echo "═══════════════════════════════════════"
echo "✅ ALL DONE"
echo "   Tunnel host: $TUNNEL_HOST"
echo "═══════════════════════════════════════"
