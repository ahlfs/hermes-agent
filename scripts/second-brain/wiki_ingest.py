#!/usr/bin/env python3
"""AI Second Brain — Wiki ingest (Karpathy "LLM wiki" pattern).

Turns raw notes in <vault>/03-Notes/ into a synthesized, interlinked wiki
under <vault>/04-Wiki/ (Entities/ + Concepts/), so the vault's Graph View
actually connects and the knowledge compounds over time.

Architecture — deliberately "Cara B" for safety:
    The agent only REASONS. It reads the schema + wiki index + a few
    relevant existing pages + one new note, and returns a single JSON object
    describing which pages to create/update. It is given NO file-write tools.
    THIS SCRIPT does every filesystem write, with strict path validation
    (pages can only ever land inside 04-Wiki/Entities or 04-Wiki/Concepts).
    So the worst a malicious/injected note can do is produce a bad wiki page,
    not write arbitrary files.

Token cost stays bounded: the agent gets index.md (a small catalog) plus
only the handful of existing pages whose titles the new note actually
mentions (grep-selected, no embeddings) — not the whole wiki.

Uses the existing `hermes` CLI (same model/credentials as chat — no separate
API key). No third-party Python deps, so plain system python3 is fine.

Env vars:
    OBSIDIAN_VAULT_DIR         vault path (preferred)
    SECOND_BRAIN_VAULT         fallback vault path (default: ~/obsidian/memo)
    HERMES_WIKI_MODEL          optional model override for `hermes -z -m ...`
    HERMES_WIKI_TIMEOUT        per-note timeout seconds (default: 180)
    HERMES_WIKI_MAX_NOTE       truncate note chars sent to the agent (default: 8000)
    HERMES_WIKI_MAX_CANDIDATES max existing pages to load as context (default: 8)
"""
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
NOTES_DIRS = [
    VAULT_ROOT / "03-Notes" / "Transcripts",
    VAULT_ROOT / "03-Notes" / "Extracted-Docs",
]
WIKI_ROOT = VAULT_ROOT / "04-Wiki"
ENTITIES_DIR = WIKI_ROOT / "Entities"
CONCEPTS_DIR = WIKI_ROOT / "Concepts"
INDEX_FILE = WIKI_ROOT / "index.md"
LOG_FILE = WIKI_ROOT / "log.md"
SCHEMA_FILE = VAULT_ROOT / "WIKI_SCHEMA.md"
STATE_FILE = VAULT_ROOT / ".wiki-state.json"

MODEL = os.environ.get("HERMES_WIKI_MODEL", "").strip()
TIMEOUT_S = int(os.environ.get("HERMES_WIKI_TIMEOUT", "180"))
MAX_NOTE_CHARS = int(os.environ.get("HERMES_WIKI_MAX_NOTE", "8000"))
MAX_CANDIDATES = int(os.environ.get("HERMES_WIKI_MAX_CANDIDATES", "8"))

# Only letters, numbers, spaces, hyphens; must sit directly under
# Entities/ or Concepts/ and end in .md. This is the security boundary.
SAFE_PATH_RE = re.compile(r"^(Entities|Concepts)/[A-Za-z0-9 _-]+\.md$")

PROMPT_TEMPLATE = """You maintain a personal knowledge wiki (Karpathy "LLM wiki" pattern). Read ONE new source note and decide which wiki pages to create or update. You do NOT write files — a script writes them from the JSON you return. Output a SINGLE JSON object and nothing else: no prose, no markdown code fences.

=== WIKI SCHEMA (follow these rules) ===
{schema}

=== CURRENT WIKI INDEX (pages that already exist — update these instead of making near-duplicates) ===
{index}

=== EXISTING PAGES THAT MAY BE RELEVANT (full content — if the note extends one of these, return its FULL merged body) ===
{candidates}

=== NEW SOURCE NOTE (filename: {note_name}) ===
{note_content}

=== OUTPUT ===
Return exactly this JSON shape:
{{
  "pages": [
    {{
      "path": "Entities/Some Name.md" OR "Concepts/Some Name.md",
      "action": "create" OR "update",
      "title": "Human Readable Title",
      "type": "entity" OR "concept",
      "category": "short, e.g. Person / Project / Tool / Topic",
      "summary": "one concise sentence for the index",
      "sources": ["{note_stem}"],
      "body": "markdown body. Use [[Wiki Links]] to connect to related pages by title. NO YAML frontmatter, NO top-level # heading — the script adds those."
    }}
  ],
  "log": "one short line describing what you did",
  "flags": ["optional: note any contradiction with an existing page"]
}}

Rules:
- path must start with Entities/ or Concepts/, use only letters/numbers/spaces/hyphens, end with .md.
- If the note is a test, empty, or has no durable content, return {{"pages": [], "log": "no durable content", "flags": []}}.
- Prefer updating an existing page over creating a near-duplicate.
- Link generously with [[Title]] to build a connected graph."""


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


def find_notes() -> list[Path]:
    notes: list[Path] = []
    for d in NOTES_DIRS:
        if d.exists():
            notes.extend(sorted(p for p in d.iterdir() if p.suffix == ".md"))
    return notes


def all_wiki_pages() -> list[Path]:
    pages: list[Path] = []
    for d in (ENTITIES_DIR, CONCEPTS_DIR):
        if d.exists():
            pages.extend(sorted(p for p in d.iterdir() if p.suffix == ".md"))
    return pages


def select_candidate_pages(note_text: str) -> list[Path]:
    """Existing pages whose title appears in the note — grep, not embeddings."""
    lowered = note_text.lower()
    hits = []
    for page in all_wiki_pages():
        title = page.stem
        if title.lower() in lowered:
            hits.append(page)
    return hits[:MAX_CANDIDATES]


def parse_frontmatter_summary(page: Path) -> str:
    try:
        text = page.read_text(encoding="utf-8")
    except OSError:
        return ""
    m = re.search(r"^summary:\s*(.+)$", text, re.MULTILINE)
    return m.group(1).strip() if m else ""


def extract_json(raw: str) -> dict | None:
    """Robustly pull a JSON object out of the model's stdout."""
    raw = raw.strip()
    # Strip ```json ... ``` fences if the model added them despite instructions.
    fence = re.search(r"```(?:json)?\s*(\{.*\})\s*```", raw, re.DOTALL)
    if fence:
        raw = fence.group(1)
    start = raw.find("{")
    end = raw.rfind("}")
    if start == -1 or end == -1 or end < start:
        return None
    try:
        return json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return None


def is_safe_path(rel_path: str) -> bool:
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


def assemble_page(page: dict, today: str) -> str:
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


def write_pages(pages: list[dict]) -> tuple[int, list[str]]:
    today = datetime.date.today().isoformat()
    written = 0
    rejected: list[str] = []
    ENTITIES_DIR.mkdir(parents=True, exist_ok=True)
    CONCEPTS_DIR.mkdir(parents=True, exist_ok=True)
    for page in pages:
        rel = page.get("path", "")
        if not isinstance(rel, str) or not is_safe_path(rel):
            rejected.append(rel or "(missing path)")
            continue
        target = WIKI_ROOT / rel
        target.write_text(assemble_page(page, today), encoding="utf-8")
        written += 1
        print(f"  -> {page.get('action', 'wrote')} {rel}")
    return written, rejected


def regenerate_index() -> None:
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


def append_log(note_name: str, log_line: str, flags: list) -> None:
    today = datetime.date.today().isoformat()
    entry = [f"## [{today}] ingest | {note_name}", f"- {log_line}"]
    for f in flags or []:
        if isinstance(f, str) and f.strip():
            entry.append(f"- ⚠ {f.strip()}")
    entry.append("")
    with LOG_FILE.open("a", encoding="utf-8") as fh:
        fh.write("\n".join(entry) + "\n")


def read_or(path: Path, fallback: str) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return fallback


def call_agent(prompt: str) -> tuple[str | None, str]:
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


def main() -> int:
    if not SCHEMA_FILE.exists():
        print(f"WIKI_SCHEMA.md not found at {SCHEMA_FILE} — cannot ingest.", file=sys.stderr)
        return 1

    notes = find_notes()
    if not notes:
        print("No notes found to ingest into the wiki.")
        return 0

    state = load_state()
    pending = [n for n in notes if state.get(str(n)) != n.stat().st_mtime]
    if not pending:
        print(f"All {len(notes)} note(s) already ingested into the wiki.")
        return 0

    print(f"Found {len(pending)} note(s) to ingest into the wiki (of {len(notes)} total).")

    schema = read_or(SCHEMA_FILE, "(schema missing)")
    failures = 0

    for note_path in pending:
        note_content = note_path.read_text(encoding="utf-8", errors="replace")
        if len(note_content) > MAX_NOTE_CHARS:
            note_content = note_content[:MAX_NOTE_CHARS] + "\n\n[...truncated...]"

        index_text = read_or(INDEX_FILE, "(empty — no pages yet)")
        candidates = select_candidate_pages(note_content)
        if candidates:
            cand_text = "\n\n".join(
                f"--- {p.relative_to(WIKI_ROOT)} ---\n{read_or(p, '')}" for p in candidates
            )
        else:
            cand_text = "(none)"

        prompt = PROMPT_TEMPLATE.format(
            schema=schema,
            index=index_text,
            candidates=cand_text,
            note_name=note_path.name,
            note_stem=note_path.stem,
            note_content=note_content,
        )

        print(f"Ingesting {note_path.relative_to(VAULT_ROOT)}...")
        stdout, err = call_agent(prompt)
        if stdout is None:
            failures += 1
            print(f"  !! {err}", file=sys.stderr)
            if "not found" in err:
                return 1
            continue

        parsed = extract_json(stdout)
        if parsed is None:
            failures += 1
            print(f"  !! could not parse JSON from agent output: {stdout.strip()[:200]}", file=sys.stderr)
            continue

        pages = parsed.get("pages") or []
        if not isinstance(pages, list):
            failures += 1
            print("  !! agent returned malformed 'pages'", file=sys.stderr)
            continue

        if not pages:
            print(f"  -> no durable content ({parsed.get('log', 'nothing to add')})")
        else:
            written, rejected = write_pages(pages)
            for r in rejected:
                print(f"  !! rejected unsafe/invalid page path: {r}", file=sys.stderr)
            regenerate_index()
            append_log(note_path.name, str(parsed.get("log", "")), parsed.get("flags", []))
            print(f"  -> {written} page(s) written; index + log updated")

        # Mark processed even when there was no durable content, so we don't
        # re-spend tokens on the same note every run.
        state[str(note_path)] = note_path.stat().st_mtime

    save_state(state)
    processed = len(pending) - failures
    print(f"Done: {processed} note(s) ingested, {failures} failed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
