#!/usr/bin/env python3
"""Cleanup source notes after successful wiki ingest.

This script removes files from:
- 03-Notes/Extracted-Docs/
- 03-Notes/Transcripts/

after they have been successfully ingested into the wiki (04-Wiki/).

The script checks the state file (.wiki-state.json) to determine which
notes have been ingested, then deletes only those that exist in both
the state AND the source folder.

This prevents accidental deletion of notes that were not processed.
"""

import json
import os
import sys
from pathlib import Path

# Add parent dir to path for _vault import
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _vault import resolve_vault

VAULT_ROOT = resolve_vault()
NOTES_DIRS = [
    VAULT_ROOT / "03-Notes" / "Transcripts",
    VAULT_ROOT / "03-Notes" / "Extracted-Docs",
]
STATE_FILE = VAULT_ROOT / ".wiki-state.json"
LOG_FILE = VAULT_ROOT / "04-Wiki" / "log.md"


def load_state() -> dict:
    """Load the wiki ingest state file."""
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"Warning: Could not load state file: {e}", file=sys.stderr)
        return {}


def load_log() -> str:
    """Load the wiki ingest log file."""
    if not LOG_FILE.exists():
        return ""
    try:
        return LOG_FILE.read_text(encoding="utf-8")
    except OSError as e:
        print(f"Warning: Could not load log file: {e}", file=sys.stderr)
        return ""


def has_wiki_page(note_path: Path, log_content: str) -> bool:
    """Check if a note has been ingested by looking for it in the log."""
    note_name = note_path.name
    # Look for the pattern: ## [date] ingest | note_name
    return f"| {note_name}" in log_content


def clean_sources() -> tuple[int, int]:
    """Clean up source notes that have been ingested.

    Returns:
        Tuple of (deleted_count, skipped_count)
    """
    state = load_state()
    log_content = load_log()
    deleted = 0
    skipped = 0

    if not state:
        print("No ingest state found. Nothing to clean.")
        return 0, 0

    print(f"Checking {len(state)} ingested note(s) for cleanup...")

    for note_path_str, mtime in state.items():
        note_path = Path(note_path_str)

        # Skip if file no longer exists (already deleted or moved)
        if not note_path.exists():
            continue

        # Verify this note was processed by our wiki ingest
        # by checking if it's in one of our expected source dirs
        in_source_dir = False
        for notes_dir in NOTES_DIRS:
            try:
                note_path.relative_to(notes_dir)
                in_source_dir = True
                break
            except ValueError:
                continue

        if not in_source_dir:
            # File exists but not in our source directories
            # This might be a manual addition - skip it
            skipped += 1
            print(f"  [skip] {note_path.name} (not in source directories)")
            continue

        # Confirm wiki page exists for this note by checking the log
        if not has_wiki_page(note_path, log_content):
            # Not found in log - skip for now
            skipped += 1
            print(f"  [skip] {note_path.name} (no ingest log entry)")
            continue

        # Delete the source file
        try:
            note_path.unlink()
            deleted += 1
            # Find the wiki pages created from this note (by extracting from log)
            # For now just report success without specific wiki page names
            print(f"  [del]  {note_path.name}")
        except OSError as e:
            print(f"  [error] Could not delete {note_path.name}: {e}", file=sys.stderr)
            skipped += 1

    print(f"\nCleanup complete: {deleted} deleted, {skipped} skipped")
    return deleted, skipped


def main() -> int:
    """Main entry point."""
    try:
        deleted, skipped = clean_sources()
        return 0  # Always succeed - this is cleanup, not core processing
    except Exception as e:
        print(f"Error during cleanup: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
