#!/bin/bash
set -e

echo "▶ Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq openvpn openssl curl wget

WORK=/tmp/openvpn-build
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

echo "▶ Generating CA..."
openssl genrsa -out ca.key 2048 2>/dev/null
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/C=US/ST=CA/L=LA/O=OpenVPN/CN=OpenVPN-CA" 2>/dev/null

echo "▶ Generating server cert..."
openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/ST=CA/L=LA/O=OpenVPN/CN=server" 2>/dev/null
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 3650 2>/dev/null

echo "▶ Generating client cert..."
openssl genrsa -out client1.key 2048 2>/dev/null
openssl req -new -key client1.key -out client1.csr \
  -subj "/C=US/ST=CA/L=LA/O=OpenVPN/CN=client1" 2>/dev/null
openssl x509 -req -in client1.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client1.crt -days 3650 2>/dev/null

echo "▶ Generating ta.key..."
openvpn --genkey secret ta.key

echo "▶ Copying files to /etc/openvpn..."
sudo mkdir -p /etc/openvpn/server
sudo mkdir -p /etc/openvpn/client
sudo cp ca.crt server.crt server.key ta.key /etc/openvpn/server/
sudo cp ca.crt client1.crt client1.key ta.key /etc/openvpn/client/

echo "▶ Writing server.conf..."
sudo tee /etc/openvpn/server/server.conf > /dev/null <<'EOF'
port 443
proto tcp-server
dev tun
ca ca.crt
cert server.crt
key server.key
dh none
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-CBC
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

echo "▶ Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

echo "▶ Setting up NAT..."
OUT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "   Outgoing interface: $OUT_IFACE"
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$OUT_IFACE" -j MASQUERADE

echo "▶ Starting OpenVPN server..."
sudo openvpn --config /etc/openvpn/server/server.conf --daemon --log /tmp/openvpn-server.log || true

echo "▶ Waiting for OpenVPN to come up..."
OPENVPN_UP=0
for i in {1..15}; do
  sleep 2
  if pgrep -f "openvpn" > /dev/null; then
    OPENVPN_UP=1
    break
  fi
  echo "  attempt $i: not up yet..."
done

echo "--- OpenVPN processes ---"
pgrep -a openvpn || echo "(none)"
echo "--- Last 20 lines of OpenVPN log ---"
sudo tail -20 /tmp/openvpn-server.log 2>/dev/null || echo "(no log)"

if [ "$OPENVPN_UP" -eq 1 ]; then
  echo "✅ OpenVPN is running on port 443 (TCP)"
  exit 0
else
  echo "❌ OpenVPN failed to start"
  exit 1
fi
