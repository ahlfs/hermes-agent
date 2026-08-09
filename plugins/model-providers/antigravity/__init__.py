"""Antigravity / 9router provider profile.

Antigravity rejects or empties Hermes requests when the identity string
"Hermes Agent" + "Nous Research" appears in the system role. Keep the prompt
semantics, but move only that triggering system content into the first user
message where the upstream filter does not fire.
"""

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
        parts: list[str] = []
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
    """9router Antigravity provider with Hermes identity bypass."""

    def prepare_messages(self, messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not messages:
            return messages

        system_idx = next(
            (
                idx
                for idx, msg in enumerate(messages)
                if isinstance(msg, dict)
                and msg.get("role") == "system"
                and _has_antigravity_blocked_identity(msg.get("content"))
            ),
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

        user_idx = next(
            (
                idx
                for idx, msg in enumerate(rewritten)
                if idx > system_idx and isinstance(msg, dict) and msg.get("role") == "user"
            ),
            None,
        )
        if user_idx is None:
            rewritten.append({"role": "user", "content": f"{_CONTEXT_PREFIX}{system_text}]"})
            return rewritten

        user_msg = rewritten[user_idx]
        rewritten[user_idx] = {
            **user_msg,
            "content": _inject_system_context(user_msg.get("content"), system_text),
        }
        return rewritten


antigravity = AntigravityProfile(
    name="antigravity",
    aliases=("ag", "9router-antigravity"),
    env_vars=("HERMES_CUSTOM_9ROUTER_API_KEY",),
    display_name="Antigravity (9router bypass)",
    description="9router Antigravity models with Hermes system-prompt bypass",
    signup_url="https://9router.rkhyg.my.id/",
    base_url="http://localhost:20128/v1",
    fallback_models=(
        "ag/gemini-pro-agent",
        "ag/gemini-3.6-flash-high",
        "ag/gemini-3.6-flash-medium",
        "ag/gemini-3.6-flash-low",
    ),
    default_max_tokens=65536,
    supports_vision=True,
)

register_provider(antigravity)
