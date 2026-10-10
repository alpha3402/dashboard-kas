#!/usr/bin/env bash
# ============================================================
# Deploy backend Dashboard Kas ke mesin ATLAS (Linux)
# ============================================================
# Jalankan DI MESIN ATLAS (root):
#   curl -fsSL https://raw.githubusercontent.com/alpha3402/dashboard-kas/main/deploy-atlas/setup.sh | bash
# atau: scp setup.sh atlas:/tmp && ssh atlas 'bash /tmp/setup.sh'
# ============================================================
set -e

APP_DIR=/opt/dashboard-kas-backend
SERVICE=dashboard-kas
CF=/usr/local/bin/cloudflared
TUNNEL=atlas-kas
DOMAIN=kas.atlastechcompany.web.id
PORT=8000

echo "==> [1/6] paket dasar"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv curl git >/dev/null

echo "==> [2/6] ambil source terbaru"
mkdir -p "$APP_DIR"
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" pull --ff-only
else
  # repo ini publik (frontend). Backend ada di subfolder deploy-atlas/.
  git clone --depth 1 https://github.com/alpha3402/dashboard-kas.git /tmp/dk-src
  cp -r /tmp/dk-src/deploy-atlas/backend/* "$APP_DIR"/ 2>/dev/null || true
  rm -rf /tmp/dk-src
fi

echo "==> [3/6] virtualenv + dependensi Python"
python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install -q --upgrade pip
"$APP_DIR/.venv/bin/pip" install -q fastapi "uvicorn[standard]" pydantic

echo "==> [4/6] cloudflared"
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fsSL -o "$CF" \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x "$CF"
fi

echo "==> [5/6] kredensial tunnel"
if [ ! -f /root/.cloudflared/atlas-kas.json ]; then
  echo "!! BELUM ADA kredensial tunnel di /root/.cloudflared/atlas-kas.json"
  echo "   Salin dari arka-pc:"
  echo "     scp ~/.cloudflared/78ac83f2-f90e-4836-bf74-4cad2ed1123d.json root@atlas:/root/.cloudflared/atlas-kas.json"
  echo "   (atau: cloudflared tunnel login  →  cloudflared tunnel token atlas-kas)"
fi
mkdir -p /root/.cloudflared

cat > /root/.cloudflared/atlas-kas.yml <<EOF
tunnel: $TUNNEL
credentials-file: /root/.cloudflared/atlas-kas.json

ingress:
  - hostname: $DOMAIN
    service: http://127.0.0.1:$PORT
  - service: http_status:404
EOF

echo "==> [6/6] systemd services (auto-start saat boot)"

cat > /etc/systemd/system/${SERVICE}.service <<EOF
[Unit]
Description=Dashboard Kas backend (FastAPI)
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
Environment=DASHBOARD_DB=$APP_DIR/db.sqlite3
ExecStart=$APP_DIR/.venv/bin/python -m uvicorn server:app --host 127.0.0.1 --port $PORT
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/${SERVICE}-tunnel.service <<EOF
[Unit]
Description=Cloudflare named tunnel ($TUNNEL)
After=network.target ${SERVICE}.service

[Service]
Type=simple
ExecStart=$CF tunnel --config /root/.cloudflared/atlas-kas.yml run $TUNNEL
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${SERVICE}.service
systemctl enable --now ${SERVICE}-tunnel.service

sleep 4
echo
echo "=== STATUS ==="
systemctl --no-pager --lines=0 status ${SERVICE}.service       || true
systemctl --no-pager --lines=0 status ${SERVICE}-tunnel.service || true
echo
echo "Tes: curl -s https://$DOMAIN/data -H 'x-auth: arkavilai|Ajudan'"
