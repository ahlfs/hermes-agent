#!/usr/bin/env python3
"""AG Bypass Proxy — transparent proxy that removes Hermes identity from system prompts.

Supports two routing modes:
  1. Default:     /v1/...  → forwards to UPSTREAM_BASE (http://localhost:3031/v1)
  2. Path-based:  /proxy/<host:port>/v1/...  → forwards to http://<host:port>/v1/...

This allows a single proxy instance to serve multiple upstream providers.

Usage:
    python3 ag_proxy.py
    # Or via systemd: systemctl --user start ag-proxy
"""

import json
import logging
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError

# ── Config ───────────────────────────────────────────────────────────────
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 8900
UPSTREAM_BASE = "http://localhost:3031/v1"

TRIGGER_TERMS = ("hermes agent", "nous research")
SAFE_SYSTEM_PROMPT = "You are a helpful AI assistant."
CONTEXT_PREFIX = "[System Context: "

# ── Logging ──────────────────────────────────────────────────────────────
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


# ── Path-based routing ───────────────────────────────────────────────────

def _resolve_upstream(path: str) -> tuple[str, str]:
    """Resolve upstream base URL and remaining path.

    /proxy/host:port/v1/chat/completions
        → upstream = "http://host:port", remaining = "/v1/chat/completions"

    /v1/chat/completions
        → upstream = UPSTREAM_BASE, remaining = "/v1/chat/completions"
    """
    if path.startswith("/proxy/"):
        rest = path[7:]  # strip "/proxy/"
        # Find where the real API path begins (/v1/, /v2/, etc.)
        slash_idx = rest.find("/")
        if slash_idx > 0:
            host_port = rest[:slash_idx]
            remaining = rest[slash_idx:]
            upstream = f"http://{host_port}"
            return upstream, remaining
    return UPSTREAM_BASE, path


def _has_blocked_identity(text: str) -> bool:
    lower = text.lower()
    return all(term in lower for term in TRIGGER_TERMS)


def _bypass_messages(messages: list) -> tuple[list, bool]:
    """Return (modified_messages, was_bypassed)."""
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

        # Resolve upstream (path-based or default)
        upstream_base, api_path = _resolve_upstream(self.path)
        upstream_url = upstream_base + api_path

        if bypassed:
            log.info("BYPASS APPLIED [model=%s] → %s", model, upstream_base)
        else:
            log.info("PASSTHROUGH [model=%s] → %s", model, upstream_base)

        headers = {"Content-Type": "application/json"}
        auth = self.headers.get("Authorization")
        if auth:
            headers["Authorization"] = auth

        req = Request(upstream_url, data=body, headers=headers, method="POST")

        try:
            with urlopen(req, timeout=300) as resp:
                self.send_response(resp.status)
                for key, val in resp.getheaders():
                    if key.lower() not in ("transfer-encoding", "connection", "content-length"):
                        self.send_header(key, val)
                self.end_headers()

                # Stream response immediately chunk by chunk to avoid client timeout
                total_bytes = 0
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    total_bytes += len(chunk)
                log.info("SUCCESS [model=%s] status=%d bytes=%d → %s", model, resp.status, total_bytes, upstream_base)
        except HTTPError as e:
            error_body = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(error_body)
            log.warning("UPSTREAM ERROR [model=%s] status=%d → %s: %s", model, e.code, upstream_base, error_body[:200].decode(errors="replace"))
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            err = json.dumps({"error": {"message": str(e), "type": "proxy_error"}}).encode()
            self.wfile.write(err)
            log.error("PROXY ERROR [model=%s] → %s: %s", model, upstream_base, e)

    def do_GET(self):
        """Forward GET requests (e.g. /v1/models) to upstream."""
        upstream_base, api_path = _resolve_upstream(self.path)
        upstream_url = upstream_base + api_path

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
        """Suppress default access log (we use our own logger)."""
        pass


def main():
    server = HTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    log.info("AG Bypass Proxy listening on %s:%d (default upstream: %s)", LISTEN_HOST, LISTEN_PORT, UPSTREAM_BASE)
    log.info("Path-based routing enabled: /proxy/<host:port>/v1/...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Proxy stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
