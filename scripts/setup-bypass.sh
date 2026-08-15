#!/bin/bash
# ===================================================================
# Auto-Injector: Monkey-Patch Bypass untuk Custom Provider
# ===================================================================
# Strategi: BUKAN mengganti provider, melainkan MENYADAP (monkey-patch)
# method prepare_messages() milik CustomProfile yang sudah ada.
# Dengan cara ini, semua fungsi asli (daftar model, config, dll) tetap utuh.
# ===================================================================

echo "==================================================================="
echo "🧙‍♂️ HERMES HACK: BYPASS INJECTOR v3.0"
echo "==================================================================="
echo "Script ini menyadap (monkey-patch) provider yang sudah ada."
echo "Model tanpa kata 'ag' = NORMAL. Model dengan 'ag' = BYPASS."
echo "Daftar model TIDAK akan hilang!"
echo "==================================================================="
echo ""

# Set paths
HERMES_DIR="$HOME/.hermes"
PLUGIN_DIR="$HERMES_DIR/plugins/model-providers/ag-bypass-patch"

echo "⏳ Memasang patch bypass..."

# Buat Direktori Plugin
mkdir -p "$PLUGIN_DIR"

# Generate plugin.yaml
cat << 'EOF' > "$PLUGIN_DIR/plugin.yaml"
name: ag-bypass-patch
kind: model-provider
version: 3.0.0
description: Monkey-patches CustomProfile to bypass system prompt for ag models
author: Hermes Hacker
EOF

# Generate __init__.py — ini TIDAK register provider baru!
# Ia hanya menyadap prepare_messages milik CustomProfile yang sudah ada.
cat << 'PYEOF' > "$PLUGIN_DIR/__init__.py"
"""AG Bypass Patch — monkey-patches CustomProfile.prepare_messages.

This plugin does NOT register a new provider. Instead, it patches the
existing CustomProfile so that models containing 'ag' in their name
get their system prompt bypassed, while all other models pass through
completely untouched. Model lists, config, and everything else stays
100% intact.
"""

from __future__ import annotations
from typing import Any

# ── Bypass helpers ────────────────────────────────────────────────────

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


def _has_blocked_identity(content: Any) -> bool:
    text = _content_text(content).lower()
    matches = all(term in text for term in _TRIGGER_TERMS)
    import sys
    sys.stderr.write(f"\n[AG-BYPASS] 🔍 Check identity. Matches: {matches}. Text preview: {text[:120]}\n")
    sys.stderr.flush()
    return matches


_IDENTITY_REPLACEMENTS = {
    "hermes agent": "Asa",
    "hermes": "Asa",
    "nous research": "CyberLab",
    "nousresearch": "CyberLab",
    "nous": "CyberLab",
}

def _sanitize_identity(text: str) -> str:
    """Ganti semua trigger terms dan identitas terkait dengan nama samaran."""
    import re
    result = text
    for original, replacement in _IDENTITY_REPLACEMENTS.items():
        result = re.sub(re.escape(original), replacement, result, flags=re.IGNORECASE)
    return result


def _inject_system_context(content: Any, system_text: str) -> Any:
    sanitized_text = _sanitize_identity(system_text)
    injected = f"{_CONTEXT_PREFIX}{sanitized_text}]"
    if isinstance(content, str):
        return f"{injected}\n\n{content}" if content else injected
    if isinstance(content, list):
        return [{"type": "text", "text": injected}, *content]
    return injected


def _dump_prompt(messages, label=""):
    """Simpan full prompt ke file untuk inspeksi."""
    import json, os
    from datetime import datetime
    dump_dir = os.path.expanduser("~/.hermes/logs")
    os.makedirs(dump_dir, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dump_path = os.path.join(dump_dir, f"prompt_dump_{ts}.json")
    with open(dump_path, "w", encoding="utf-8") as f:
        json.dump({"label": label, "messages": messages}, f, indent=2, ensure_ascii=False)
    import sys
    sys.stderr.write(f"[AG-BYPASS] 📝 Full prompt disimpan ke: {dump_path}\n")
    sys.stderr.flush()


def _bypass_prepare_messages(original_fn):
    """Wrapper yang menyadap prepare_messages milik CustomProfile."""

    def patched_prepare_messages(self, messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not messages:
            return original_fn(self, messages)

        # Intip stack frame untuk mendapatkan nama model
        import inspect
        import sys
        
        def dash_log(msg):
            sys.stderr.write(msg + "\n")
            sys.stderr.flush()
            
        model_name = ""
        try:
            frame = inspect.currentframe().f_back
            for _ in range(5):
                if not frame:
                    break
                if "model" in frame.f_locals:
                    model_name = str(frame.f_locals["model"]).lower()
                    break
                frame = frame.f_back
        except Exception:
            pass
            
        # Jika nama model TIDAK mengandung "ag", jalankan fungsi asli tanpa bypass
        from datetime import datetime
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        if "ag" not in model_name:
            dash_log(f"[AG-BYPASS] [{timestamp}] REQUEST: Model = '{model_name}'. Status: SKIPPED (not an 'ag' model).")
            return original_fn(self, messages)

        # === BYPASS AKTIF ===
        log_msg = f"[AG-BYPASS] [{timestamp}] REQUEST: Model = '{model_name}'. Status: BYPASS ACTIVATED. "
        
        messages = original_fn(self, messages)

        system_idx = next(
            (
                idx
                for idx, msg in enumerate(messages)
                if isinstance(msg, dict)
                and msg.get("role") == "system"
                and _has_blocked_identity(msg.get("content"))
            ),
            None,
        )
        
        if system_idx is None:
            dash_log(log_msg + "Result: Failed (No 'system' role or identity triggers not found).")
            _dump_prompt(messages, "BYPASS_FAILED_no_triggers")
            return messages

        system_msg = messages[system_idx]
        system_text = _content_text(system_msg.get("content")).strip()
        if not system_text:
            dash_log(log_msg + "Result: Failed (Empty system prompt).")
            return messages

        rewritten = list(messages)
        rewritten[system_idx] = {**system_msg, "content": _SAFE_SYSTEM_PROMPT}

        user_idx = next(
            (
                idx
                for idx, msg in enumerate(rewritten)
                if idx > system_idx
                and isinstance(msg, dict)
                and msg.get("role") == "user"
            ),
            None,
        )

        if user_idx is None:
            rewritten.append(
                {"role": "user", "content": f"{_CONTEXT_PREFIX}{_sanitize_identity(system_text)}]"}
            )
            dash_log(log_msg + "Result: Success (Appended context to new user message).")
            _dump_prompt(rewritten, "BYPASS_SUCCESS_appended")
            return rewritten

        user_msg = rewritten[user_idx]
        rewritten[user_idx] = {
            **user_msg,
            "content": _inject_system_context(user_msg.get("content"), system_text),
        }
        
        dash_log(log_msg + "Result: Success (Injected context into existing user message).")
        _dump_prompt(rewritten, "BYPASS_SUCCESS_injected")
        return rewritten

    return patched_prepare_messages


# ── Patch saat import ─────────────────────────────────────────────────
# Ketika Hermes memuat plugin ini, kode di bawah langsung dieksekusi.
# Ia mencari CustomProfile dan mengganti method-nya secara langsung.

def _apply_patch():
    import sys
    sys.stderr.write("\n[AG-BYPASS] 🚀 Plugin bypass dimuat! Mencoba memasang patch ke provider...\n")
    sys.stderr.flush()
        
    try:
        from plugins import _loaded_model_providers  # noqa: F401
    except ImportError:
        pass

    # Import CustomProfile dari plugin custom bawaan Hermes
    try:
        # Path 1: Plugin-based custom provider
        from importlib import import_module
        custom_mod = import_module("plugins.model-providers.custom")
        CustomProfile = custom_mod.CustomProfile
        sys.stderr.write("[AG-BYPASS] ✅ Patch dipasang pada CustomProfile (Path 1)\n")
        sys.stderr.flush()
    except Exception:
        try:
            # Path 2: Langsung dari providers
            from providers.base import ProviderProfile
            CustomProfile = ProviderProfile
            sys.stderr.write("[AG-BYPASS] ✅ Patch dipasang pada ProviderProfile (Path 2)\n")
            sys.stderr.flush()
        except Exception:
            sys.stderr.write("[AG-BYPASS] ❌ GAGAL: Tidak menemukan ProviderProfile atau CustomProfile!\n")
            sys.stderr.flush()
            return

    # Simpan referensi fungsi asli
    _original = CustomProfile.prepare_messages

    # Tempelkan fungsi bypass sebagai pengganti
    CustomProfile.prepare_messages = _bypass_prepare_messages(_original)


_apply_patch()
PYEOF

echo "✅ Patch bypass berhasil dipasang di: $PLUGIN_DIR"
echo ""
echo "==================================================================="
echo "🎉 INJEKSI v3.0 SELESAI! 🎉"
echo "==================================================================="
echo "Plugin ini TIDAK membuat provider baru."
echo "Ia hanya menyadap (monkey-patch) CustomProfile yang sudah ada."
echo "- Daftar model Anda TETAP UTUH (tidak akan 0 models lagi!)."
echo "- Model tanpa 'ag' = NORMAL, model dengan 'ag' = BYPASS."
echo ""
echo "Jalankan 'pkill -f hermes' untuk me-restart daemon sekarang."
echo "==================================================================="
echo ""
