#!/bin/bash
set -e

echo "▶ Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq openvpn easy-rsa openssl curl wget

echo "▶ Setting up directories..."
sudo mkdir -p /etc/openvpn/server
sudo mkdir -p /etc/openvpn/client
sudo rm -rf /etc/openvpn/easy-rsa
sudo mkdir -p /etc/openvpn/easy-rsa

echo "▶ Copying easy-rsa..."
sudo cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/
cd /etc/openvpn/easy-rsa

echo "▶ Building PKI..."
sudo ./easyrsa init-pki > /dev/null
sudo ./easyrsa --batch build-ca nopass > /dev/null
sudo ./easyrsa --batch gen-req server nopass > /dev/null
sudo ./easyrsa --batch sign-req server server > /dev/null
sudo ./easyrsa --batch gen-req client1 nopass > /dev/null
sudo ./easyrsa --batch sign-req client client1 > /dev/null

echo "▶ Generating ta.key and dh.pem..."
sudo openvpn --genkey secret /etc/openvpn/server/ta.key
sudo openssl dhparam -out /etc/openvpn/server/dh.pem 2048

echo "▶ Copying server certs..."
sudo cp pki/ca.crt /etc/openvpn/server/
sudo cp pki/issued/server.crt /etc/openvpn/server/
sudo cp pki/private/server.key /etc/openvpn/server/

echo "▶ Writing server.conf..."
sudo tee /etc/openvpn/server/server.conf > /dev/null <<'EOF'
port 443
proto tcp-server
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-CBC
auth SHA256
compress lz4-v2
push "compress lz4-v2"
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
sudo openvpn --config /etc/openvpn/server/server.conf --daemon
sleep 3

if pgrep -x openvpn > /dev/null; then
  echo "✅ OpenVPN is running on port 443 (TCP)"
else
  echo "❌ OpenVPN failed to start"
  sudo tail -50 /var/log/syslog | grep -i openvpn || true
  exit 1
fi
