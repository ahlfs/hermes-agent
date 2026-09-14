#!/usr/bin/env python3
"""Generate a compact wiki digest for AI agent consumption.

Reads all wiki pages from 04-Wiki/ and produces a condensed markdown
summary (title + category + summary per page) that can be injected
into agent context without burning excessive tokens.

Output: $OBSIDIAN_VAULT_DIR/04-Wiki/DIGEST.md

This digest enables the agent to know WHAT knowledge exists in the wiki
and decide which pages to read in full when needed.
"""
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _vault import resolve_vault

VAULT_ROOT = resolve_vault()
WIKI_ROOT = VAULT_ROOT / "04-Wiki"
DIGEST_FILE = WIKI_ROOT / "DIGEST.md"


def parse_frontmatter(filepath: Path) -> dict:
    """Extract YAML frontmatter fields from a wiki page."""
    try:
        text = filepath.read_text(encoding="utf-8")
    except OSError:
        return {}

    if not text.startswith("---"):
        return {}

    end = text.find("---", 3)
    if end == -1:
        return {}

    fm_text = text[3:end]
    result = {}
    for line in fm_text.strip().split("\n"):
        if ":" in line:
            key, _, val = line.partition(":")
            result[key.strip()] = val.strip()
    return result


def main() -> int:
    lines = [
        "# Wiki Knowledge Digest",
        "",
        "_Compact index of all Second Brain wiki pages._",
        f"_Generated from {WIKI_ROOT}_",
        "",
    ]

    for label, subdir in [("Concepts", "Concepts"), ("Entities", "Entities")]:
        dirpath = WIKI_ROOT / subdir
        if not dirpath.exists():
            continue

        pages = sorted(p for p in dirpath.iterdir() if p.suffix == ".md")
        lines.append(f"## {label} ({len(pages)})")
        lines.append("")

        for page in pages:
            fm = parse_frontmatter(page)
            title = fm.get("title", page.stem)
            category = fm.get("category", "")
            summary = fm.get("summary", "")
            tags = fm.get("tags", "")

            entry = f"- **{title}**"
            if category:
                entry += f" [{category}]"
            if summary:
                entry += f" — {summary}"
            lines.append(entry)

        lines.append("")

    content = "\n".join(lines)
    DIGEST_FILE.write_text(content, encoding="utf-8")

    # Count stats
    total_chars = len(content)
    concept_count = len(list((WIKI_ROOT / "Concepts").iterdir())) if (WIKI_ROOT / "Concepts").exists() else 0
    entity_count = len(list((WIKI_ROOT / "Entities").iterdir())) if (WIKI_ROOT / "Entities").exists() else 0

    print(f"Wiki digest generated: {DIGEST_FILE}")
    print(f"  {concept_count} concepts + {entity_count} entities = {concept_count + entity_count} pages")
    print(f"  Digest size: {total_chars} chars ({total_chars // 4} tokens approx)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
