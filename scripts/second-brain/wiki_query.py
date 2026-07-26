#!/usr/bin/env python3
"""AI Second Brain — Wiki query (Karpathy "LLM wiki" pattern).

Searches the wiki for relevant pages, synthesizes a cited answer, and
optionally compounds the answer into a new wiki page.

Architecture — same "Cara B" as wiki_ingest.py:
    The agent only REASONS. It receives the question + relevant wiki pages
    and returns a JSON object with the answer and optional new page. THIS
    SCRIPT does every filesystem write, with the same strict path validation.

Uses the existing `hermes` CLI (same model/credentials as chat — no separate
API key). No third-party Python deps, so plain system python3 is fine.

Env vars:
    OBSIDIAN_VAULT_DIR         vault path (preferred)
    SECOND_BRAIN_VAULT         fallback vault path (default: ~/obsidian/memo)
    HERMES_WIKI_MODEL          optional model override for `hermes -z -m ...`
    HERMES_WIKI_TIMEOUT        query timeout seconds (default: 120)
    HERMES_WIKI_MAX_CANDIDATES max pages to load as context (default: 8)
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _vault import resolve_vault

VAULT_ROOT = resolve_vault()
WIKI_ROOT = VAULT_ROOT / "04-Wiki"
ENTITIES_DIR = WIKI_ROOT / "Entities"
CONCEPTS_DIR = WIKI_ROOT / "Concepts"
INDEX_FILE = WIKI_ROOT / "index.md"
LOG_FILE = WIKI_ROOT / "log.md"
SCHEMA_FILE = VAULT_ROOT / "WIKI_SCHEMA.md"

MODEL = os.environ.get("HERMES_WIKI_MODEL", "").strip()
TIMEOUT_S = int(os.environ.get("HERMES_WIKI_TIMEOUT", "120"))
MAX_CANDIDATES = int(os.environ.get("HERMES_WIKI_MAX_CANDIDATES", "8"))

# Security boundary — same as wiki_ingest.py
SAFE_PATH_RE = re.compile(r"^(Entities|Concepts)/[A-Za-z0-9 _-]+\.md$")

QUERY_PROMPT = """You are a knowledge assistant that answers questions ONLY from the user's personal wiki. Do NOT use your general training knowledge — if the wiki doesn't contain the answer, say so honestly.

=== WIKI INDEX (all pages that exist) ===
{index}

=== RELEVANT WIKI PAGES (full content) ===
{pages_content}

=== QUESTION ===
{question}

=== OUTPUT ===
Return a SINGLE JSON object and nothing else (no prose, no markdown code fences):
{{
  "answer": "Your answer in markdown. Cite wiki pages with [[Page Title]] links. Be concise but thorough.",
  "sources": ["Page Title 1", "Page Title 2"],
  "confidence": "high" | "medium" | "low" | "not_found",
  "new_page": null OR {{
    "path": "Concepts/Some New Topic.md",
    "action": "create",
    "title": "Some New Topic",
    "type": "concept",
    "category": "short category",
    "summary": "one concise sentence for the index",
    "sources": ["query"],
    "body": "markdown body synthesized from the answer. Use [[Wiki Links]]. NO YAML frontmatter, NO top-level # heading."
  }}
}}

Rules:
- Answer ONLY from the wiki content provided. If the information isn't there, set confidence to "not_found" and explain what's missing.
- Link generously with [[Title]] to connect your answer to wiki pages.
- Set new_page ONLY if your answer synthesizes a genuinely new concept/entity that doesn't already exist as a page and would be valuable to persist. Most queries should return new_page: null.
- path in new_page must start with Entities/ or Concepts/, use only letters/numbers/spaces/hyphens, end with .md."""


# ---------------------------------------------------------------------------
# Helpers (reused from wiki_ingest.py patterns)
# ---------------------------------------------------------------------------

def all_wiki_pages() -> list[Path]:
    """Return all .md files under Entities/ and Concepts/."""
    pages: list[Path] = []
    for d in (ENTITIES_DIR, CONCEPTS_DIR):
        if d.exists():
            pages.extend(sorted(p for p in d.iterdir() if p.suffix == ".md"))
    return pages


def read_or(path: Path, fallback: str) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return fallback


def select_relevant_pages(question: str, pages: list[Path]) -> list[Path]:
    """Select wiki pages relevant to the question via keyword grep."""
    # Tokenize the question into meaningful words (3+ chars)
    words = [w.lower() for w in re.findall(r"[A-Za-z0-9]+", question) if len(w) >= 3]
    if not words:
        return pages[:MAX_CANDIDATES]

    scored: list[tuple[Path, int]] = []
    for page in pages:
        title_lower = page.stem.lower()
        content_lower = read_or(page, "").lower()

        score = 0
        for word in words:
            # Title match is worth more
            if word in title_lower:
                score += 3
            if word in content_lower:
                score += 1
        if score > 0:
            scored.append((page, score))

    # Sort by score descending, take top N
    scored.sort(key=lambda x: x[1], reverse=True)
    return [p for p, _ in scored[:MAX_CANDIDATES]]


def extract_json(raw: str) -> dict | None:
    """Robustly pull a JSON object out of the model's stdout."""
    raw = raw.strip()
    # Strip ```json ... ``` fences
    fence = re.search(r"```(?:json)?\s*(\{.*\})\s*```", raw, re.DOTALL)
    if fence:
        raw = fence.group(1)
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end < start:
        return None
    try:
        return json.loads(raw[start: end + 1])
    except json.JSONDecodeError:
        return None


def is_safe_path(rel_path: str) -> bool:
    """Validate that a page path is safe (same check as wiki_ingest.py)."""
    if ".." in rel_path or rel_path.startswith("/"):
        return False
    if not SAFE_PATH_RE.match(rel_path):
        return False
    resolved = (WIKI_ROOT / rel_path).resolve()
    try:
        resolved.relative_to(WIKI_ROOT.resolve())
    except ValueError:
        return False
    return True


def parse_frontmatter_summary(page: Path) -> str:
    try:
        text = page.read_text(encoding="utf-8")
    except OSError:
        return ""
    m = re.search(r"^summary:\s*(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else ""


def assemble_page(page: dict, today: str) -> str:
    """Build a wiki page from agent JSON (same format as wiki_ingest.py)."""
    sources = page.get("sources") or []
    source_links = ", ".join(f"[[{s}]]" for s in sources if isinstance(s, str) and s)
    fm = [
        "---",
        f"type: {page.get('type', 'concept')}",
        f"category: {page.get('category', '')}",
        f"summary: {page.get('summary', '').replace(chr(10), ' ')}",
        f"sources: {source_links}",
        f"updated: {today}",
        "---",
        "",
        f"# {page.get('title', page['path'])}",
        "",
        (page.get("body") or "").strip(),
        "",
    ]
    return "\n".join(fm)


def regenerate_index() -> None:
    """Regenerate index.md from all wiki pages (same as wiki_ingest.py)."""
    lines = [
        "# Wiki Index",
        "",
        "_Auto-generated by `scripts/wiki_ingest.py` — do not hand-edit._",
        "",
    ]
    for label, d in (("Entities", ENTITIES_DIR), ("Concepts", CONCEPTS_DIR)):
        pages = sorted(p for p in d.iterdir() if p.suffix == ".md") if d.exists() else []
        lines.append(f"## {label}")
        lines.append("")
        if not pages:
            lines.append("_(none yet)_")
        for p in pages:
            summary = parse_frontmatter_summary(p)
            link = f"[[{p.stem}]]"
            lines.append(f"- {link}" + (f" — {summary}" if summary else ""))
        lines.append("")
    INDEX_FILE.write_text("\n".join(lines), encoding="utf-8")


def append_log(question: str, log_line: str) -> None:
    """Append a query event to log.md."""
    today = datetime.date.today().isoformat()
    entry = [
        f"## [{today}] query",
        f"- Q: {question[:100]}",
        f"- {log_line}",
        "",
    ]
    with LOG_FILE.open("a", encoding="utf-8") as fh:
        fh.write("\n".join(entry) + "\n")


def call_agent(prompt: str) -> tuple[str | None, str]:
    """Call hermes -z with the given prompt."""
    cmd = ["hermes", "-z", prompt]
    if MODEL:
        cmd += ["-m", MODEL]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)
    except FileNotFoundError:
        return None, "hermes CLI not found on PATH"
    except subprocess.TimeoutExpired:
        return None, f"timed out after {TIMEOUT_S}s"
    if result.returncode != 0:
        return None, f"hermes exited {result.returncode}: {result.stderr.strip()[:300]}"
    return result.stdout, ""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Query the AI Second Brain wiki."
    )
    parser.add_argument(
        "question", type=str,
        help="The question to ask the wiki.",
    )
    parser.add_argument(
        "--compound", action="store_true",
        help="If the agent suggests a new page, create it (knowledge compounding).",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Output the full JSON response instead of just the answer.",
    )
    args = parser.parse_args()

    if not WIKI_ROOT.exists():
        print("Wiki directory not found — nothing to query.", file=sys.stderr)
        return 1

    pages = all_wiki_pages()
    if not pages:
        print("Wiki is empty — ingest some notes first.", file=sys.stderr)
        return 1

    # Find relevant pages
    relevant = select_relevant_pages(args.question, pages)
    if not relevant:
        # Fall back to all pages if nothing matches
        relevant = pages[:MAX_CANDIDATES]

    # Build context
    index_text = read_or(INDEX_FILE, "(empty — no pages yet)")
    pages_content = "\n\n".join(
        f"--- {p.stem} ---\n{read_or(p, '(empty)')}" for p in relevant
    )

    prompt = QUERY_PROMPT.format(
        index=index_text,
        pages_content=pages_content,
        question=args.question,
    )

    # Call agent
    stdout, err = call_agent(prompt)
    if stdout is None:
        print(f"Error: {err}", file=sys.stderr)
        return 1

    parsed = extract_json(stdout)
    if parsed is None:
        print(f"Could not parse JSON from agent output: {stdout.strip()[:300]}", file=sys.stderr)
        return 1

    answer = parsed.get("answer", "(no answer)")
    confidence = parsed.get("confidence", "unknown")
    sources = parsed.get("sources", [])
    new_page = parsed.get("new_page")

    # Handle compounding
    compounded = False
    if args.compound and new_page and isinstance(new_page, dict):
        rel_path = new_page.get("path", "")
        if isinstance(rel_path, str) and is_safe_path(rel_path):
            target = WIKI_ROOT / rel_path
            if not target.exists():
                ENTITIES_DIR.mkdir(parents=True, exist_ok=True)
                CONCEPTS_DIR.mkdir(parents=True, exist_ok=True)
                today = datetime.date.today().isoformat()
                target.write_text(assemble_page(new_page, today), encoding="utf-8")
                regenerate_index()
                append_log(args.question, f"compounded → {rel_path}")
                compounded = True
            else:
                # Page already exists — don't overwrite
                pass
        else:
            print(f"  !! rejected unsafe/invalid new_page path: {rel_path}", file=sys.stderr)

    # Output
    if args.json:
        output = {
            "question": args.question,
            "answer": answer,
            "confidence": confidence,
            "sources": sources,
            "compounded": compounded,
            "new_page_path": new_page.get("path") if compounded and new_page else None,
        }
        print(json.dumps(output, indent=2, ensure_ascii=False))
    else:
        print(f"\n{'─' * 60}")
        print(f"  Pertanyaan: {args.question}")
        print(f"  Confidence: {confidence}")
        print(f"  Sources: {', '.join(sources) if sources else '(none)'}")
        print(f"{'─' * 60}\n")
        print(answer)
        if compounded and new_page:
            print(f"\n📝 Compounded: new page created → {new_page.get('path')}")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
