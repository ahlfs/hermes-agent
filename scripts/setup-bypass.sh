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

# 1. Pastikan ag_proxy.py ada di folder scripts/
if [ ! -f "$AG_PROXY_SCRIPT" ]; then
    echo "📄 Membuat scripts/ag_proxy.py..."
    cat << 'PYEOF' > "$AG_PROXY_SCRIPT"
#!/usr/bin/env python3
"""AG Bypass Proxy — transparent proxy that removes Hermes identity from system prompts.

Listens on port 8900 and forwards to the upstream 9router Antigravity endpoint (port 3031).
Detects "Hermes Agent" + "Nous Research" in the system role and moves the
identity to a user message as [System Context: ...].
"""

import json
import logging
import re
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8900
UPSTREAM_BASE = "http://localhost:3031/v1"

TRIGGER_TERMS = ("hermes agent", "nous research")
SAFE_SYSTEM_PROMPT = "You are a helpful AI assistant."
CONTEXT_PREFIX = "[System Context: "

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stderr),
        logging.FileHandler("/tmp/ag_proxy.log"),
    ],
)
log = logging.getLogger("ag-proxy")


def _has_blocked_identity(text: str) -> bool:
    lower = text.lower()
    return all(term in lower for term in TRIGGER_TERMS)


def _bypass_messages(messages: list) -> tuple[list, bool]:
    system_idx = None
    for i, msg in enumerate(messages):
        if isinstance(msg, dict) and msg.get("role") == "system":
            content = msg.get("content", "")
            if isinstance(content, str) and _has_blocked_identity(content):
                system_idx = i
                break

    if system_idx is None:
        return messages, False

    system_text = messages[system_idx].get("content", "").strip()
    if not system_text:
        return messages, False

    rewritten = list(messages)
    rewritten[system_idx] = {**messages[system_idx], "content": SAFE_SYSTEM_PROMPT}

    user_idx = None
    for i, msg in enumerate(rewritten):
        if i > system_idx and isinstance(msg, dict) and msg.get("role") == "user":
            user_idx = i
            break

    context_injection = f"{CONTEXT_PREFIX}{system_text}]"

    if user_idx is None:
        rewritten.append({"role": "user", "content": context_injection})
    else:
        user_content = rewritten[user_idx].get("content", "")
        if isinstance(user_content, str):
            rewritten[user_idx] = {
                **rewritten[user_idx],
                "content": f"{context_injection}\n\n{user_content}" if user_content else context_injection,
            }
        elif isinstance(user_content, list):
            rewritten[user_idx] = {
                **rewritten[user_idx],
                "content": [{"type": "text", "text": context_injection}, *user_content],
            }

    return rewritten, True


class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = None

        bypassed = False
        if payload and "messages" in payload:
            payload["messages"], bypassed = _bypass_messages(payload["messages"])
            body = json.dumps(payload).encode("utf-8")

        model = payload.get("model", "unknown") if payload else "unknown"
        if bypassed:
            log.info("BYPASS APPLIED: moved identity to user context [model=%s]", model)
        else:
            log.info("PASSTHROUGH: no bypass needed [model=%s]", model)

        upstream_url = UPSTREAM_BASE + self.path
        headers = {"Content-Type": "application/json"}
        auth = self.headers.get("Authorization")
        if auth:
            headers["Authorization"] = auth

        req = Request(upstream_url, data=body, headers=headers, method="POST")

        try:
            with urlopen(req, timeout=300) as resp:
                resp_body = resp.read()
                self.send_response(resp.status)
                for key, val in resp.getheaders():
                    if key.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(key, val)
                self.end_headers()
                self.wfile.write(resp_body)
                log.info("SUCCESS [model=%s] status=%d bytes=%d", model, resp.status, len(resp_body))
        except HTTPError as e:
            error_body = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(error_body)
            log.warning("UPSTREAM ERROR [model=%s] status=%d: %s", model, e.code, error_body[:200].decode(errors="replace"))
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            err = json.dumps({"error": {"message": str(e), "type": "proxy_error"}}).encode()
            self.wfile.write(err)
            log.error("PROXY ERROR [model=%s]: %s", model, e)

    def do_GET(self):
        upstream_url = UPSTREAM_BASE + self.path
        headers = {}
        auth = self.headers.get("Authorization")
        if auth:
            headers["Authorization"] = auth

        req = Request(upstream_url, headers=headers, method="GET")
        try:
            with urlopen(req, timeout=30) as resp:
                resp_body = resp.read()
                self.send_response(resp.status)
                for key, val in resp.getheaders():
                    if key.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(key, val)
                self.end_headers()
                self.wfile.write(resp_body)
        except HTTPError as e:
            error_body = e.read()
            self.send_response(e.code)
            self.end_headers()
            self.wfile.write(error_body)
        except Exception as e:
            self.send_response(502)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def main():
    server = HTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    log.info("AG Bypass Proxy listening on %s:%d → %s", LISTEN_HOST, LISTEN_PORT, UPSTREAM_BASE)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Proxy stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$AG_PROXY_SCRIPT"
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
    "$HERMES_BIN" config set providers.antigravity.models '["ag/gemini-pro-agent", "ag/gemini-3.6-flash-high", "ag/gemini-3.6-flash-medium", "ag/gemini-3.6-flash-low"]'
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
echo "  - Cek status proxy:  systemctl --user status ag-proxy"
echo "  - Cek log proxy:     tail -f /tmp/ag_proxy.log"
echo "==================================================================="
