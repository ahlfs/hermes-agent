#!/bin/bash
# ===================================================================
# Antigravity Provider Setup Script for Hermes Agent
# ===================================================================

# Set variables
HERMES_DIR="$HOME/.hermes"
PLUGIN_DIR="$HERMES_DIR/plugins/model-providers/antigravity"
CONFIG_FILE="$HERMES_DIR/config.yaml"

echo "🚀 Memulai instalasi plugin Antigravity untuk Hermes Agent..."

# 1. Create plugin directory
echo "📂 Membuat direktori plugin di $PLUGIN_DIR..."
mkdir -p "$PLUGIN_DIR"

# 2. Generate plugin.yaml
echo "📄 Membuat file manifest (plugin.yaml)..."
cat << 'EOF' > "$PLUGIN_DIR/plugin.yaml"
name: antigravity-provider
kind: model-provider
version: 1.0.0
description: 9router Antigravity models with Hermes system-prompt bypass
author: Ahlfs (Custom)
EOF

# 3. Generate __init__.py (The bypass logic)
echo "🧠 Menyuntikkan logika bypass (__init__.py)..."
cat << 'EOF' > "$PLUGIN_DIR/__init__.py"
"""Antigravity / 9router provider profile bypass."""

from __future__ import annotations
from typing import Any
from providers import register_provider
from providers.base import ProviderProfile

_TRIGGER_TERMS = ("hermes agent", "nous research")
_SAFE_SYSTEM_PROMPT = "You are a helpful AI assistant."
_CONTEXT_PREFIX = "[System Context: "

def _content_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str):
                    parts.append(text)
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts)
    return ""

def _has_antigravity_blocked_identity(content: Any) -> bool:
    text = _content_text(content).lower()
    return all(term in text for term in _TRIGGER_TERMS)

def _inject_system_context(content: Any, system_text: str) -> Any:
    injected = f"{_CONTEXT_PREFIX}{system_text}]"
    if isinstance(content, str):
        return f"{injected}\n\n{content}" if content else injected
    if isinstance(content, list):
        return [{"type": "text", "text": injected}, *content]
    return injected

class AntigravityProfile(ProviderProfile):
    def prepare_messages(self, messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not messages:
            return messages

        system_idx = next(
            (idx for idx, msg in enumerate(messages) if isinstance(msg, dict) and msg.get("role") == "system" and _has_antigravity_blocked_identity(msg.get("content"))),
            None,
        )
        if system_idx is None:
            return messages

        system_msg = messages[system_idx]
            
        system_text = _content_text(system_msg.get("content")).strip()
        if not system_text:
            return messages

        rewritten = list(messages)
        rewritten[system_idx] = {**system_msg, "content": _SAFE_SYSTEM_PROMPT}

        user_idx = next((idx for idx, msg in enumerate(rewritten) if idx > system_idx and isinstance(msg, dict) and msg.get("role") == "user"), None)
        
        if user_idx is None:
            rewritten.append({"role": "user", "content": f"{_CONTEXT_PREFIX}{system_text}]"})
            return rewritten

        user_msg = rewritten[user_idx]
        rewritten[user_idx] = {**user_msg, "content": _inject_system_context(user_msg.get("content"), system_text)}
        return rewritten

antigravity = AntigravityProfile(
    name="antigravity",
    aliases=("ag", "9router-antigravity"),
    env_vars=("HERMES_CUSTOM_9ROUTER_API_KEY",),
    display_name="Antigravity (9router bypass)",
    description="9router Antigravity models with Hermes system-prompt bypass",
    signup_url="https://9router.rkhyg.my.id/",
    base_url="http://localhost:20128/v1",
    fallback_models=("ag/gemini-pro-agent", "ag/gemini-3.6-flash-high"),
    default_max_tokens=65536,
    supports_vision=True,
)

register_provider(antigravity)
EOF

# 4. Modify config.yaml to set the provider
echo "⚙️  Mengonfigurasi config.yaml..."
if [ -f "$CONFIG_FILE" ]; then
    # Backup file config sebelum dimodifikasi
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak_antigravity"
    
    # Memodifikasi setting provider menjadi antigravity
    awk '/^model:/ {in_model=1} in_model && /^  provider:/ {print "  provider: antigravity"; in_model=0; next} {print}' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    # Menambahkan blok custom_providers agar lolos validasi CLI
    if ! grep -q "id: antigravity" "$CONFIG_FILE"; then
        if grep -q "^custom_providers:" "$CONFIG_FILE"; then
            # Insert tepat di bawah baris custom_providers:
            awk '/^custom_providers:/ {
                print
                print "  - name: antigravity"
                print "    id: antigravity"
                print "    base_url: http://localhost:20128/v1"
                print "    api_key_env: HERMES_CUSTOM_9ROUTER_API_KEY"
                print "    models:"
                print "      - ag/gemini-pro-agent"
                print "      - ag/gemini-3.6-flash-high"
                print "      - ag/gemini-3.6-flash-medium"
                print "      - ag/gemini-3.6-flash-low"
                next
            } {print}' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        else
            # Jika belum ada sama sekali, tambahkan di paling bawah
            echo "" >> "$CONFIG_FILE"
            echo "custom_providers:" >> "$CONFIG_FILE"
            cat << 'EOF' >> "$CONFIG_FILE"
  - name: antigravity
    id: antigravity
    base_url: http://localhost:20128/v1
    api_key_env: HERMES_CUSTOM_9ROUTER_API_KEY
    models:
      - ag/gemini-pro-agent
      - ag/gemini-3.6-flash-high
      - ag/gemini-3.6-flash-medium
      - ag/gemini-3.6-flash-low
EOF
        fi
    fi
    
    echo "✅ Konfigurasi berhasil diubah. Backup config disimpan di ${CONFIG_FILE}.bak_antigravity"
else
    echo "⚠️ File config.yaml tidak ditemukan di $CONFIG_FILE. Silakan atur provider secara manual."
fi

# 5. Provide final instructions to user
echo ""
echo "==================================================================="
echo "🎉 INSTALASI PLUGIN ANTIGRAVITY SELESAI! 🎉"
echo "==================================================================="
echo "Langkah terakhir yang harus Anda lakukan secara MANUAl (demi keamanan):"
echo "1. Buka file: ~/.hermes/.env"
echo "2. Masukkan API Key Anda: HERMES_CUSTOM_9ROUTER_API_KEY=kunci_rahasia"
echo "3. Jalankan perintah ini untuk merestart daemon:"
echo "   pkill -f hermes"
echo "==================================================================="
echo ""
