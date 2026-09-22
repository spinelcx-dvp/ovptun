
#!/usr/bin/env python3
import http.server
import socketserver
import os

PORT = 8080
TUNNEL_HOST_FILE = "/tmp/tunnel_host.txt"
OVPN_OUTPUT = "/tmp/client.ovpn"

def build_ovpn():
    with open(TUNNEL_HOST_FILE) as f:
        host = f.read().strip()

    with open("/etc/openvpn/client/ca.crt") as f:
        ca = f.read()
    with open("/etc/openvpn/client/client1.crt") as f:
        cert = f.read()
    with open("/etc/openvpn/client/client1.key") as f:
        key = f.read()
    with open("/etc/openvpn/client/ta.key") as f:
        ta = f.read()

    config = f"""client
dev tun
proto tcp-client
remote {host} 443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
compress lz4-v2
verb 3
<ca>
{ca}
</ca>
<cert>
{cert}
</cert>
<key>
{key}
</key>
<tls-auth>
{ta}
</tls-auth>
key-direction 1
"""
    with open(OVPN_OUTPUT, "w") as f:
        f.write(config)
    return host

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                host = build_ovpn()
                error = None
            except Exception as e:
                host = "N/A"
                error = str(e)

            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()

            err_block = f'<p class="warn">خطا: {error}</p>' if error else ""
            html = f"""<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<title>OpenVPN Panel</title>
<style>
  body {{ font-family: Tahoma, sans-serif; background:#0f0f0f; color:#eee;
         display:flex; justify-content:center; align-items:center;
         height:100vh; margin:0; }}
  .card {{ background:#1e1e1e; padding:40px 50px; border-radius:16px;
          text-align:center; box-shadow:0 0 30px #000; max-width:90%; }}
  h1 {{ color:#4ade80; margin-top:0; }}
  .host {{ background:#2a2a2a; padding:12px; border-radius:8px;
          font-family:monospace; direction:ltr; margin:20px 0;
          color:#4ade80; word-break:break-all; }}
  a.btn {{ display:inline-block; background:#4ade80; color:#000;
          padding:14px 28px; border-radius:8px; text-decoration:none;
          font-weight:bold; margin-top:10px; transition:0.2s; }}
  a.btn:hover {{ background:#22c55e; }}
  .warn {{ color:#f87171; font-size:13px; margin-top:20px; }}
  .info {{ color:#94a3b8; font-size:13px; margin-top:10px; }}
</style>
</head>
<body>
<div class="card">
  <h1>✅ OpenVPN Ready</h1>
  <p>سرور فعال است</p>
  <div class="host">{host}:443 (TCP)</div>
  <a class="btn" href="/download">⬇️ دانلود کانفیگ .ovpn</a>
  <p class="info">پروتکل: TCP | رمزنگاری: AES-256-CBC</p>
  <p class="warn">⚠️ این آدرس موقت است و پس از پایان اجرا از کار می‌افتد</p>
  {err_block}
</div>
</body>
</html>"""
            self.wfile.write(html.encode())
        elif self.path == "/download":
            try:
                build_ovpn()
                self.send_response(200)
                self.send_header("Content-type", "application/x-openvpn-profile")
                self.send_header("Content-Disposition", "attachment; filename=client.ovpn")
                self.end_headers()
                with open(OVPN_OUTPUT, "rb") as f:
                    self.wfile.write(f.read())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(f"Error: {e}".encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass

if __name__ == "__main__":
    build_ovpn()
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"✅ Panel running on http://0.0.0.0:{PORT}")
        httpd.serve_forever()
