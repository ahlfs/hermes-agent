"""Shared vault-path resolution for all Second Brain scripts.

Reads OBSIDIAN_VAULT_DIR first (canonical, set in ~/.hermes/.env),
falls back to SECOND_BRAIN_VAULT for backward compatibility with
scripts that were originally in lam-cyberlab.
"""
import os
from pathlib import Path


def resolve_vault() -> Path:
    """Return the resolved, absolute Path to the Obsidian vault."""
    raw = (
        os.environ.get("OBSIDIAN_VAULT_DIR")
        or os.environ.get("SECOND_BRAIN_VAULT")
        or "~/obsidian/memo"
    )
    return Path(raw).expanduser().resolve()
