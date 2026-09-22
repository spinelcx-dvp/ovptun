#!/bin/bash
set -e

echo "▶ Cleaning up..."
sudo rm -rf /tmp/openvpn-build 2>/dev/null || true
sudo rm -f /tmp/chisel* 2>/dev/null || true
sudo rm -f /tmp/tunnel*.log 2>/dev/null || true

echo "═══════════════════════════════════════"
echo "▶ Step 1: Downloading chisel..."
echo "═══════════════════════════════════════"

CHISEL_URL="https://github.com/jpillora/chisel/releases/download/v1.9.1/chisel_1.9.1_linux_amd64.gz"

download_ok=0
for attempt in 1 2 3; do
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
echo "▶ Step 3: Creating SSH key"
echo "═══════════════════════════════════════"

mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N "" -q
chmod 600 ~/.ssh/id_rsa

ssh-keyscan -t rsa localhost.run >> ~/.ssh/known_hosts 2>/dev/null || true

echo "  SSH key created"

echo ""
echo "═══════════════════════════════════════"
echo "▶ Step 4: Starting localhost.run tunnel"
echo "═══════════════════════════════════════"

nohup ssh -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -R 80:localhost:8080 \
  nokey@localhost.run \
  > /tmp/tunnel.log 2>&1 &

TUNNEL_URL=""
for i in {1..45}; do
  if grep -qE "https://[a-zA-Z0-9.-]+\.lhr\.life" /tmp/tunnel.log 2>/dev/null; then
    TUNNEL_URL=$(grep -oE 'https://[a-zA-Z0-9.-]+\.lhr\.life' /tmp/tunnel.log | head -1)
    break
  fi
  if ! pgrep -f "ssh.*localhost.run" > /dev/null; then
    echo "❌ SSH tunnel process died"
    echo "--- tunnel.log ---"
    cat /tmp/tunnel.log
    exit 1
  fi
  if [ $((i % 10)) -eq 0 ]; then
    echo "  waited $((i*2))s..."
    tail -3 /tmp/tunnel.log
  fi
  sleep 2
done

if [ -z "$TUNNEL_URL" ]; then
  echo "❌ Failed to get tunnel URL after 90s"
  echo "--- tunnel.log ---"
  cat /tmp/tunnel.log
  exit 1
fi

TUNNEL_HOST=$(echo "$TUNNEL_URL" | sed 's|https://||')
echo "$TUNNEL_HOST" > /tmp/tunnel_host.txt

echo ""
echo "═══════════════════════════════════════"
echo "✅ ALL DONE"
echo "   Tunnel URL : $TUNNEL_URL"
echo "   Tunnel host: $TUNNEL_HOST"
echo "═══════════════════════════════════════"
