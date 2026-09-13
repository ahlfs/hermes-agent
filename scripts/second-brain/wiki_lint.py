#!/usr/bin/env python3
"""AI Second Brain — Wiki lint (Karpathy "LLM wiki" pattern).

Detects quality issues ("wiki rot") in the 04-Wiki/ layer:
  1. Orphan pages      — pages no other page links to
  2. Dangling links    — [[links]] pointing to non-existent pages
  3. Stale pages       — pages not updated in N days
  4. Missing sources   — pages citing source notes that no longer exist
  5. Duplicate candidates — pages with very similar names (possible dupes)
  6. Contradictions    — conflicting claims between linked pages (LLM, optional)

This script NEVER modifies or deletes wiki pages — it only reports.
The user or agent decides what to do with the findings.

Env vars (same as wiki_ingest.py):
    OBSIDIAN_VAULT_DIR     vault path (preferred)
    SECOND_BRAIN_VAULT     fallback vault path (default: ~/obsidian/memo)
    HERMES_WIKI_MODEL      optional model override for contradiction check
    HERMES_WIKI_TIMEOUT    per-pair timeout seconds (default: 120)
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _vault import resolve_vault

VAULT_ROOT = resolve_vault()
WIKI_ROOT = VAULT_ROOT / "04-Wiki"
ENTITIES_DIR = WIKI_ROOT / "Entities"
CONCEPTS_DIR = WIKI_ROOT / "Concepts"
NOTES_DIRS = [
    VAULT_ROOT / "03-Notes" / "Transcripts",
    VAULT_ROOT / "03-Notes" / "Extracted-Docs",
]

MODEL = os.environ.get("HERMES_WIKI_MODEL", "").strip()
TIMEOUT_S = int(os.environ.get("HERMES_WIKI_TIMEOUT", "120"))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def all_wiki_pages() -> list[Path]:
    """Return all .md files under Entities/ and Concepts/."""
    pages: list[Path] = []
    for d in (ENTITIES_DIR, CONCEPTS_DIR):
        if d.exists():
            pages.extend(sorted(p for p in d.iterdir() if p.suffix == ".md"))
    return pages


def all_source_notes() -> set[str]:
    """Return stems of all source notes in 03-Notes/."""
    stems: set[str] = set()
    for d in NOTES_DIRS:
        if d.exists():
            for p in d.iterdir():
                if p.suffix == ".md":
                    stems.add(p.stem)
    return stems


def read_page(path: Path) -> str:
    """Read a wiki page, returning empty string on error."""
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def extract_wikilinks(text: str) -> list[str]:
    """Extract all [[wiki link]] targets from text."""
    return re.findall(r"\[\[([^\]]+)\]\]", text)


def parse_frontmatter(text: str) -> dict[str, str]:
    """Parse YAML frontmatter into a flat dict of string values."""
    fm: dict[str, str] = {}
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return fm
    for line in m.group(1).splitlines():
        sep = line.find(":")
        if sep > 0:
            key = line[:sep].strip()
            val = line[sep + 1:].strip()
            fm[key] = val
    return fm


def similarity(a: str, b: str) -> float:
    """Simple character-level Jaccard similarity between two strings."""
    a_lower = a.lower().replace(" ", "").replace("-", "").replace("_", "")
    b_lower = b.lower().replace(" ", "").replace("-", "").replace("_", "")
    if not a_lower or not b_lower:
        return 0.0
    a_set = set(a_lower)
    b_set = set(b_lower)
    intersection = len(a_set & b_set)
    union = len(a_set | b_set)
    return intersection / union if union else 0.0


def levenshtein_ratio(a: str, b: str) -> float:
    """Normalized Levenshtein similarity (1.0 = identical)."""
    a_low = a.lower()
    b_low = b.lower()
    if a_low == b_low:
        return 1.0
    len_a, len_b = len(a_low), len(b_low)
    if not len_a or not len_b:
        return 0.0
    # Simple DP
    matrix = [[0] * (len_b + 1) for _ in range(len_a + 1)]
    for i in range(len_a + 1):
        matrix[i][0] = i
    for j in range(len_b + 1):
        matrix[0][j] = j
    for i in range(1, len_a + 1):
        for j in range(1, len_b + 1):
            cost = 0 if a_low[i - 1] == b_low[j - 1] else 1
            matrix[i][j] = min(
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost,
            )
    max_len = max(len_a, len_b)
    return 1.0 - (matrix[len_a][len_b] / max_len)


# ---------------------------------------------------------------------------
# Lint checks
# ---------------------------------------------------------------------------

class LintResult:
    """Accumulates findings from all checks."""

    def __init__(self):
        self.warnings: list[dict] = []
        self.skipped: list[str] = []

    def warn(self, check: str, message: str, details: list[str] | None = None):
        self.warnings.append({
            "check": check,
            "message": message,
            "details": details or [],
        })

    def skip(self, check: str):
        self.skipped.append(check)

    @property
    def count(self) -> int:
        return len(self.warnings)


def check_orphan_pages(pages: list[Path], page_links: dict[str, list[str]]) -> list[str]:
    """Find pages that no other page links to."""
    all_titles = {p.stem for p in pages}
    linked_titles: set[str] = set()
    for links in page_links.values():
        linked_titles.update(links)
    # A page is orphan if no other page links TO it
    orphans = []
    for title in sorted(all_titles):
        if title not in linked_titles:
            orphans.append(title)
    return orphans


def check_dangling_links(pages: list[Path], page_links: dict[str, list[str]]) -> list[tuple[str, str]]:
    """Find [[links]] that point to non-existent wiki pages."""
    all_titles = {p.stem for p in pages}
    # Also consider source notes as valid link targets
    source_stems = all_source_notes()
    valid = all_titles | source_stems
    danglers: list[tuple[str, str]] = []
    for page_title, links in page_links.items():
        for link in links:
            if link not in valid:
                danglers.append((link, page_title))
    return danglers


def check_stale_pages(pages: list[Path], stale_days: int) -> list[tuple[str, int]]:
    """Find pages whose 'updated' frontmatter is older than N days."""
    today = datetime.date.today()
    stale: list[tuple[str, int]] = []
    for p in pages:
        text = read_page(p)
        fm = parse_frontmatter(text)
        updated_str = fm.get("updated", "")
        if not updated_str:
            # No date = treat as stale
            stale.append((p.stem, -1))
            continue
        try:
            updated_date = datetime.date.fromisoformat(updated_str)
            age = (today - updated_date).days
            if age > stale_days:
                stale.append((p.stem, age))
        except ValueError:
            stale.append((p.stem, -1))
    return stale


def check_missing_sources(pages: list[Path]) -> list[tuple[str, list[str]]]:
    """Find pages whose sources: frontmatter cites notes that don't exist."""
    existing_notes = all_source_notes()
    issues: list[tuple[str, list[str]]] = []
    for p in pages:
        text = read_page(p)
        fm = parse_frontmatter(text)
        sources_raw = fm.get("sources", "")
        # sources look like: [[MODUL_1_2]], [[other_note]]
        cited = re.findall(r"\[\[([^\]]+)\]\]", sources_raw)
        missing = [s for s in cited if s not in existing_notes]
        if missing:
            issues.append((p.stem, missing))
    return issues


def check_duplicate_candidates(pages: list[Path], threshold: float = 0.85) -> list[tuple[str, str, float]]:
    """Find page pairs with very similar names."""
    titles = [p.stem for p in pages]
    dupes: list[tuple[str, str, float]] = []
    seen: set[tuple[str, str]] = set()
    for i, a in enumerate(titles):
        for b in titles[i + 1:]:
            if a == b:
                continue
            pair = (min(a, b), max(a, b))
            if pair in seen:
                continue
            seen.add(pair)
            ratio = levenshtein_ratio(a, b)
            if ratio >= threshold:
                dupes.append((a, b, ratio))
    return dupes


CONTRADICTION_PROMPT = """You are a wiki consistency auditor. Compare two wiki pages and identify factual contradictions (NOT mere differences in scope or detail — only actual conflicts).

=== PAGE A: {title_a} ===
{content_a}

=== PAGE B: {title_b} ===
{content_b}

If there are contradictions, return a JSON array of short strings describing each one.
If there are NO contradictions, return an empty array: []
Return ONLY the JSON array, no prose, no code fences."""


def check_contradictions(pages: list[Path], page_links: dict[str, list[str]]) -> list[dict]:
    """Use LLM to detect contradictions between linked pages."""
    all_titles = {p.stem: p for p in pages}
    checked: set[tuple[str, str]] = set()
    findings: list[dict] = []

    for title, links in page_links.items():
        if title not in all_titles:
            continue
        for linked_title in links:
            if linked_title not in all_titles:
                continue
            pair = (min(title, linked_title), max(title, linked_title))
            if pair in checked:
                continue
            checked.add(pair)

            content_a = read_page(all_titles[title])
            content_b = read_page(all_titles[linked_title])

            prompt = CONTRADICTION_PROMPT.format(
                title_a=title, content_a=content_a[:4000],
                title_b=linked_title, content_b=content_b[:4000],
            )

            cmd = ["hermes", "-z", prompt]
            if MODEL:
                cmd += ["-m", MODEL]
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S)
            except (FileNotFoundError, subprocess.TimeoutExpired):
                continue
            if result.returncode != 0:
                continue

            raw = result.stdout.strip()
            # Try to parse JSON array
            start = raw.find("[")
            end = raw.rfind("]")
            if start != -1 and end > start:
                try:
                    items = json.loads(raw[start:end + 1])
                    if isinstance(items, list) and items:
                        findings.append({
                            "pages": [title, linked_title],
                            "contradictions": [str(c) for c in items],
                        })
                except json.JSONDecodeError:
                    pass

    return findings


# ---------------------------------------------------------------------------
# Report formatting
# ---------------------------------------------------------------------------

def format_text_report(result: LintResult, pages: list[Path]) -> str:
    """Format a human-readable lint report."""
    lines = [
        "== Wiki Lint Report ==",
        f"   Pages scanned: {len(pages)}",
        f"   Date: {datetime.date.today().isoformat()}",
        "",
    ]

    checks_seen: set[str] = set()
    for w in result.warnings:
        checks_seen.add(w["check"])

    all_checks = [
        "orphan_pages", "dangling_links", "stale_pages",
        "missing_sources", "duplicate_candidates", "contradictions",
    ]
    check_labels = {
        "orphan_pages": "Orphan pages",
        "dangling_links": "Dangling links",
        "stale_pages": "Stale pages",
        "missing_sources": "Missing sources",
        "duplicate_candidates": "Duplicate candidates",
        "contradictions": "Contradictions",
    }

    for check in all_checks:
        label = check_labels.get(check, check)
        if check in result.skipped:
            lines.append(f"⏭  {label}: [skipped]")
            continue
        matching = [w for w in result.warnings if w["check"] == check]
        if not matching:
            lines.append(f"✅ {label}: none found")
        else:
            total_details = sum(len(w["details"]) for w in matching)
            count = total_details if total_details else len(matching)
            lines.append(f"⚠  {label} ({count}):")
            for w in matching:
                if w["details"]:
                    for d in w["details"]:
                        lines.append(f"   - {d}")
                else:
                    lines.append(f"   - {w['message']}")
        lines.append("")

    lines.append(f"Summary: {result.count} warning(s)")
    return "\n".join(lines)


def format_markdown_report(result: LintResult, pages: list[Path]) -> str:
    """Format a markdown lint report for saving to the vault."""
    lines = [
        "# Wiki Lint Report",
        "",
        f"_Auto-generated by `scripts/wiki_lint.py` on {datetime.date.today().isoformat()}._",
        f"_Pages scanned: {len(pages)}_",
        "",
    ]

    check_labels = {
        "orphan_pages": "Orphan Pages",
        "dangling_links": "Dangling Links",
        "stale_pages": "Stale Pages",
        "missing_sources": "Missing Sources",
        "duplicate_candidates": "Duplicate Candidates",
        "contradictions": "Contradictions",
    }

    all_checks = list(check_labels.keys())
    for check in all_checks:
        label = check_labels[check]
        if check in result.skipped:
            lines.append(f"## {label}")
            lines.append("")
            lines.append("_Skipped (--no-llm)_")
            lines.append("")
            continue

        matching = [w for w in result.warnings if w["check"] == check]
        lines.append(f"## {label}")
        lines.append("")
        if not matching:
            lines.append("✅ No issues found.")
        else:
            for w in matching:
                if w["details"]:
                    for d in w["details"]:
                        lines.append(f"- ⚠ {d}")
                else:
                    lines.append(f"- ⚠ {w['message']}")
        lines.append("")

    lines.append(f"---")
    lines.append(f"**Total warnings: {result.count}**")
    return "\n".join(lines)


def format_json_report(result: LintResult, pages: list[Path]) -> str:
    """Format a JSON lint report."""
    return json.dumps({
        "date": datetime.date.today().isoformat(),
        "pages_scanned": len(pages),
        "warnings": result.warnings,
        "skipped": result.skipped,
        "total_warnings": result.count,
    }, indent=2, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lint the AI Second Brain wiki for quality issues."
    )
    parser.add_argument(
        "--no-llm", action="store_true",
        help="Skip LLM-based checks (contradiction detection). Free checks only.",
    )
    parser.add_argument(
        "--stale-days", type=int, default=30,
        help="Threshold for stale page detection (default: 30 days).",
    )
    parser.add_argument(
        "--save-report", action="store_true",
        help="Save the report to 04-Wiki/lint-report.md.",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Output in JSON format instead of human-readable text.",
    )
    args = parser.parse_args()

    if not WIKI_ROOT.exists():
        print("Wiki directory not found — nothing to lint.", file=sys.stderr)
        return 0

    pages = all_wiki_pages()
    if not pages:
        print("No wiki pages found — nothing to lint.")
        return 0

    # Build the link graph: title -> [linked titles]
    page_links: dict[str, list[str]] = {}
    for p in pages:
        text = read_page(p)
        # Strip frontmatter before extracting links (avoid parsing sources as content links)
        body_start = text.find("---", 3)
        body = text[body_start + 3:] if body_start > 0 else text
        links = extract_wikilinks(body)
        page_links[p.stem] = links

    result = LintResult()

    # Check 1: Orphan pages
    orphans = check_orphan_pages(pages, page_links)
    if orphans:
        result.warn("orphan_pages", f"{len(orphans)} orphan page(s)", [
            f"[[{t}]] — not linked by any other wiki page" for t in orphans
        ])

    # Check 2: Dangling links
    danglers = check_dangling_links(pages, page_links)
    if danglers:
        result.warn("dangling_links", f"{len(danglers)} dangling link(s)", [
            f"[[{link}]] (referenced by: {src}.md)" for link, src in danglers
        ])

    # Check 3: Stale pages
    stale = check_stale_pages(pages, args.stale_days)
    if stale:
        result.warn("stale_pages", f"{len(stale)} stale page(s)", [
            f"[[{title}]] — {'no date' if age < 0 else f'{age} days old'}"
            for title, age in stale
        ])

    # Check 4: Missing sources
    missing = check_missing_sources(pages)
    if missing:
        details = []
        for title, sources in missing:
            details.append(f"[[{title}]] cites missing: {', '.join(sources)}")
        result.warn("missing_sources", f"{len(missing)} page(s) with missing sources", details)

    # Check 5: Duplicate candidates
    dupes = check_duplicate_candidates(pages)
    if dupes:
        result.warn("duplicate_candidates", f"{len(dupes)} potential duplicate(s)", [
            f'"{a}" vs "{b}" (similarity: {score:.2f})' for a, b, score in dupes
        ])

    # Check 6: Contradictions (LLM)
    if args.no_llm:
        result.skip("contradictions")
    else:
        contradictions = check_contradictions(pages, page_links)
        if contradictions:
            details = []
            for c in contradictions:
                pair = " ↔ ".join(c["pages"])
                for item in c["contradictions"]:
                    details.append(f"{pair}: {item}")
            result.warn("contradictions", f"{len(contradictions)} contradiction(s)", details)

    # Output
    if args.json:
        report = format_json_report(result, pages)
    else:
        report = format_text_report(result, pages)
    print(report)

    if args.save_report:
        report_path = WIKI_ROOT / "lint-report.md"
        report_path.write_text(format_markdown_report(result, pages), encoding="utf-8")
        print(f"\nReport saved to {report_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
