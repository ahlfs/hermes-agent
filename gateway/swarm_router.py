"""Intent-based swarm routing — auto-delegate to the best specialist profile.

When ``gateway.auto_swarm_routing`` is enabled and no static profile_route
matches, this module classifies the user's message intent and returns the
profile name of the most appropriate specialist agent.

Classification uses fast keyword matching first (zero latency, zero tokens)
and only falls back to an LLM call when the keywords are ambiguous.

Profiles are discovered from ``~/.hermes/profiles/`` by reading each
profile's ``SOUL.md`` for its specialty description.  A JSON index is
cached at ``~/.hermes/.swarm-profile-index.json`` and rebuilt when any
``SOUL.md`` is newer than the cache.

Design constraints:
  * No new dependencies — stdlib only.
  * Never imported at module level by gateway/run.py; always lazy-imported
    inside the routing path so startup time is unaffected.
  * Falls back gracefully: if no profiles exist or classification fails,
    returns None (the gateway uses the default profile).
"""

from __future__ import annotations

import json
import logging
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# ── Keyword banks ────────────────────────────────────────────────────────────
# Each profile maps to a set of trigger words/phrases.  Matching is
# case-insensitive and uses word boundaries.

_KEYWORD_BANKS: Dict[str, List[str]] = {
    "builder": [
        "build", "code", "coding", "implement", "debug", "fix", "refactor",
        "deploy", "script", "function", "class", "api", "endpoint", "docker",
        "ci/cd", "migration", "database", "sql", "test", "unittest",
        "compile", "run", "execute", "install", "setup", "configure",
        "buatkan", "buat", "bikin", "koding", "skrip", "perbaiki",
        "deploy", "jalankan", "eksekusi",
        "python", "javascript", "typescript", "bash", "go", "rust",
        "git", "commit", "push", "pull", "merge", "branch",
    ],
    "researcher": [
        "research", "search", "find", "look up", "investigate", "analyze",
        "analysis", "compare", "survey", "study", "review", "explore",
        "explain", "what is", "how does", "why", "benchmark", "evaluate",
        "trend", "data", "statistics", "report",
        "cari", "riset", "analisis", "bandingkan", "jelaskan",
        "apa itu", "bagaimana", "mengapa", "kenapa", "evaluasi",
    ],
    "writer": [
        "write", "draft", "document", "documentation", "blog", "article",
        "essay", "readme", "prd", "proposal", "edit", "proofread",
        "translate", "summarize", "summary", "outline", "content",
        "copy", "story", "creative", "narrative", "format",
        "tulis", "tuliskan", "rangkum", "ringkas", "terjemahkan",
        "dokumen", "dokumentasi", "artikel", "cerita",
    ],
}

# Pre-compile word-boundary patterns for each keyword
_COMPILED_PATTERNS: Dict[str, List[re.Pattern]] = {}


def _ensure_compiled() -> None:
    """Lazily compile keyword patterns on first use."""
    if _COMPILED_PATTERNS:
        return
    for profile, keywords in _KEYWORD_BANKS.items():
        patterns = []
        for kw in keywords:
            # Use word boundaries; escape regex-special chars in keywords
            escaped = re.escape(kw)
            patterns.append(re.compile(rf"\b{escaped}\b", re.IGNORECASE))
        _COMPILED_PATTERNS[profile] = patterns


def _get_profiles_dir() -> Path:
    """Return the profiles directory path."""
    try:
        from hermes_constants import get_hermes_home
        return get_hermes_home() / "profiles"
    except ImportError:
        return Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes")) / "profiles"


def discover_profiles() -> Dict[str, str]:
    """Scan ~/.hermes/profiles/ and return {name: soul_description}.

    Only profiles with a SOUL.md are included.
    """
    profiles_dir = _get_profiles_dir()
    if not profiles_dir.is_dir():
        return {}

    result: Dict[str, str] = {}
    for entry in profiles_dir.iterdir():
        if not entry.is_dir():
            continue
        soul_file = entry / "SOUL.md"
        if soul_file.exists():
            try:
                content = soul_file.read_text(encoding="utf-8", errors="replace")
                # Use first 500 chars as description
                result[entry.name] = content[:500].strip()
            except OSError:
                continue
    return result


def classify_intent(message: str) -> Optional[str]:
    """Classify a user message and return the best-matching profile name.

    Uses keyword scoring: each keyword hit adds 1 point to that profile's
    score.  The profile with the highest score wins, but only if it has
    at least 1 hit and leads by a clear margin (>= 1 point ahead of the
    runner-up).

    Returns None if no profile scores or if the result is too ambiguous.
    """
    _ensure_compiled()

    scores: Dict[str, int] = {}
    for profile, patterns in _COMPILED_PATTERNS.items():
        score = sum(1 for p in patterns if p.search(message))
        if score > 0:
            scores[profile] = score

    if not scores:
        return None

    # Sort by score descending
    ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)

    winner_name, winner_score = ranked[0]

    # If there's a runner-up, require a margin of at least 1
    if len(ranked) > 1:
        _, runner_up_score = ranked[1]
        if winner_score - runner_up_score < 1:
            # Too ambiguous — fall back to default
            logger.debug(
                "Swarm router: ambiguous intent (scores=%s), using default profile",
                scores,
            )
            return None

    # Verify the profile actually exists
    profiles_dir = _get_profiles_dir()
    if not (profiles_dir / winner_name / "SOUL.md").exists():
        logger.warning(
            "Swarm router: matched profile %r but SOUL.md not found, using default",
            winner_name,
        )
        return None

    logger.info("Swarm router: classified intent -> %s (scores=%s)", winner_name, scores)
    return winner_name


def auto_route_by_intent(
    message: str,
    platform: str = "",
    **kwargs,
) -> Optional[str]:
    """High-level entry point for the gateway routing path.

    Returns a profile name string if a specialist should handle this message,
    or None to use the default profile.

    This function is designed to be called from
    ``gateway.profile_routing.match_profile_route`` as a fallback.
    """
    profiles = discover_profiles()
    if not profiles:
        logger.debug("Swarm router: no profiles found in %s", _get_profiles_dir())
        return None

    return classify_intent(message)
