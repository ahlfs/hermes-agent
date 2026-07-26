#!/usr/bin/env python3
"""AI Second Brain — memory consolidation pass.

Scans <vault>/03-Notes/{Transcripts,Extracted-Docs}/ for notes that haven't
been consolidated yet, and asks Hermes Agent (via `hermes -z` one-shot mode)
to pull out anything durably worth remembering and save it using its own
memory tool — the same MEMORY.md/USER.md the agent already reads on every
session. This is what makes the vault actually feed back into chat, instead
of sitting as searchable-but-inert storage.

Only the `memory` toolset is enabled for these one-shot runs (`-t memory`),
so a note can only ever result in a memory write — not arbitrary tool use —
even if its content contains something adversarial (e.g. a meeting
transcript that happens to quote injected instructions). Still, this does
run untrusted content through an agent with --yolo; treat that as a real,
bounded risk, not a solved one.

No third-party Python deps — this just shells out to the `hermes` CLI, so
plain system python3 is fine (no venv needed).

Env vars:
    OBSIDIAN_VAULT_DIR             path to the Obsidian vault (preferred)
    SECOND_BRAIN_VAULT             fallback vault path (default: ~/obsidian/memo)
    HERMES_CONSOLIDATE_TIMEOUT     per-note timeout in seconds (default: 120)
    HERMES_CONSOLIDATE_MAX_CHARS   truncate note content sent per prompt (default: 8000)
"""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _vault import resolve_vault

VAULT_ROOT = resolve_vault()
NOTE_DIRS = [
    VAULT_ROOT / "03-Notes" / "Transcripts",
    VAULT_ROOT / "03-Notes" / "Extracted-Docs",
]
STATE_FILE = VAULT_ROOT / ".second-brain-state.json"

TIMEOUT_S = int(os.environ.get("HERMES_CONSOLIDATE_TIMEOUT", "120"))
MAX_CHARS = int(os.environ.get("HERMES_CONSOLIDATE_MAX_CHARS", "8000"))

PROMPT_TEMPLATE = """You are reviewing a note from the user's second-brain vault (a voice transcript or extracted document) to decide what, if anything, is worth remembering long-term.

Note filename: {name}

Note content:
---
{content}
---

If this note contains durable facts worth remembering (user preferences, decisions, project details, recurring people/topics, commitments, etc.), use your memory tool to save them now, in your own words, concise. If there's genuinely nothing worth remembering (e.g. a test recording, empty content, pure noise), do nothing and say so — do not save filler."""


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
    notes = []
    for note_dir in NOTE_DIRS:
        if note_dir.exists():
            notes.extend(sorted(p for p in note_dir.iterdir() if p.suffix == ".md"))
    return notes


def main() -> int:
    notes = find_notes()
    if not notes:
        print("No notes found to consolidate.")
        return 0

    state = load_state()
    pending = [n for n in notes if state.get(str(n)) != n.stat().st_mtime]

    if not pending:
        print(f"All {len(notes)} note(s) already consolidated into memory.")
        return 0

    print(f"Found {len(pending)} note(s) to consolidate (of {len(notes)} total).")

    failures = 0
    for note_path in pending:
        content = note_path.read_text(encoding="utf-8", errors="replace")
        if len(content) > MAX_CHARS:
            content = content[:MAX_CHARS] + "\n\n[...truncated...]"

        prompt = PROMPT_TEMPLATE.format(name=note_path.name, content=content)
        print(f"Consolidating {note_path.relative_to(VAULT_ROOT)}...")
        try:
            result = subprocess.run(
                ["hermes", "-z", prompt, "-t", "memory", "--yolo"],
                capture_output=True,
                text=True,
                timeout=TIMEOUT_S,
            )
        except FileNotFoundError:
            print("hermes CLI not found on PATH.", file=sys.stderr)
            return 1
        except subprocess.TimeoutExpired:
            failures += 1
            print(f"  !! timed out after {TIMEOUT_S}s", file=sys.stderr)
            continue

        if result.returncode != 0:
            failures += 1
            print(f"  !! hermes exited {result.returncode}: {result.stderr.strip()[:300]}", file=sys.stderr)
            continue

        summary = result.stdout.strip().replace("\n", " ")[:200]
        print(f"  -> {summary}")
        state[str(note_path)] = note_path.stat().st_mtime

    save_state(state)
    processed = len(pending) - failures
    print(f"Done: {processed} consolidated, {failures} failed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
