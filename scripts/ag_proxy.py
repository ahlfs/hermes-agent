#!/usr/bin/env python3
"""AG Bypass Proxy — transparent proxy that removes Hermes identity from system prompts.

Listens on port 8900 and forwards to the upstream 9router Antigravity endpoint.
Detects "Hermes Agent" + "Nous Research" in the system role and moves the
identity to a user message as [System Context: ...].

Usage:
    python3 ~/ag_proxy.py
    # Or via systemd: systemctl --user start ag-proxy
"""

import json
import logging
import re
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

    # Find first user message after system
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

        # Forward to upstream
        upstream_url = UPSTREAM_BASE + self.path
        headers = {
            "Content-Type": "application/json",
        }
        # Forward auth header
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
        """Forward GET requests (e.g. /v1/models) to upstream."""
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
        """Suppress default access log (we use our own logger)."""
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
