#!/bin/bash
# ===================================================================
# Setup AG Proxy Bypass untuk Hermes Agent
# ===================================================================
# Menyiapkan ag_proxy.py (port 8900 -> 3031), mengonfigurasi systemd
# user service ag-proxy, serta mengatur provider config Hermes.
# ===================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_DIR="$HOME/.hermes"
AG_PROXY_SCRIPT="$SCRIPT_DIR/ag_proxy.py"
SERVICE_FILE="$HOME/.config/systemd/user/ag-proxy.service"

echo "==================================================================="
echo "🧙‍♂️ HERMES SETUP: AG PROXY BYPASS"
echo "==================================================================="
echo "Script ini mengonfigurasi Proxy Transparan (port 8900 -> port 3031)"
echo "untuk mem-bypass pembatasan identitas Hermes Agent di Antigravity."
echo "==================================================================="
echo ""

# 1. Pastikan ag_proxy.py ada di folder scripts/ (salin dari source jika belum ada)
if [ ! -f "$AG_PROXY_SCRIPT" ]; then
    echo "📄 ag_proxy.py tidak ditemukan, mohon pastikan file ada di: $AG_PROXY_SCRIPT"
    exit 1
fi

# 2. Buat systemd service unit
echo "⚙️  Menyiapkan systemd service (ag-proxy.service)..."
mkdir -p "$HOME/.config/systemd/user"
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=AG Bypass Proxy for Hermes (port 8900 -> 3031)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $AG_PROXY_SCRIPT
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

# Reload & Restart systemd service
systemctl --user daemon-reload
systemctl --user enable ag-proxy.service
systemctl --user restart ag-proxy.service
echo "✅ Service ag-proxy aktif di port 8900"

# 3. Bersihkan plugin monkey-patch lama jika ada
rm -rf "$HERMES_DIR/plugins/model-providers/ag-bypass-patch"

# 4. Konfigurasi Hermes CLI jika binary hermes tersedia
HERMES_BIN="$SCRIPT_DIR/venv/bin/hermes"
if [ ! -x "$HERMES_BIN" ]; then
    HERMES_BIN="$(which hermes 2>/dev/null || true)"
fi

if [ -x "$HERMES_BIN" ]; then
    echo "🔧 Mengonfigurasi Hermes config..."
    "$HERMES_BIN" config set providers.antigravity.base_url "http://127.0.0.1:8900/v1"
    "$HERMES_BIN" config set providers.antigravity.key_env "HERMES_CUSTOM_9ROUTER_API_KEY"
    "$HERMES_BIN" config set providers.antigravity.models '["ag/gemini-pro-agent","ag/gemini-3.6-flash-high","ag/gemini-3.6-flash-medium","ag/gemini-3.6-flash-low"]'
    "$HERMES_BIN" config set providers.antigravity.discover_models false
fi

# 5. Restart daemon hermes
pkill -f hermes 2>/dev/null || true

echo ""
echo "==================================================================="
echo "🎉 SETUP AG PROXY SELESAI! 🎉"
echo "==================================================================="
echo "Alur Koneksi:"
echo "  Hermes → http://127.0.0.1:8900/v1 (Proxy) → http://localhost:3031/v1 (Bridge)"
echo ""
echo "Perintah berguna:"
echo "  - Cek status proxy:     systemctl --user status ag-proxy"
echo "  - Cek log proxy:        tail -f /tmp/ag_proxy.log"
echo "  - Kelola routing:       bash scripts/route-provider.sh"
echo "==================================================================="
echo ""

# 6. Tawarkan routing provider tambahan
ROUTE_SCRIPT="$SCRIPT_DIR/route-provider.sh"
if [ -f "$ROUTE_SCRIPT" ]; then
    echo "💡 Ingin mengatur provider lain agar melewati AG Proxy?"
    read -p "   Jalankan Route Provider sekarang? (y/n, default: n): " run_route
    if [ "$run_route" = "y" ] || [ "$run_route" = "Y" ]; then
        bash "$ROUTE_SCRIPT"
    fi
fi
