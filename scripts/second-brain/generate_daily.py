#!/usr/bin/env python3
"""
Daily Activity Logger for Second Brain.
Reads yesterday's conversation logs and uses Hermes AI to generate a comprehensive
daily journal with YAML frontmatter, wikilinks to known projects/concepts, and structured sections.
"""

import sys
import os
from datetime import datetime, timedelta
from pathlib import Path

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore
from sb_utils import call_hermes_api, get_chat_history  # type: ignore

vault_dir = resolve_vault()
daily_dir = vault_dir / "07-Daily"
projects_dir = vault_dir / "05-Projects"
wiki_index_file = vault_dir / "04-Wiki" / "index.md"
daily_dir.mkdir(parents=True, exist_ok=True)

# We are summarizing "yesterday"
yesterday_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
daily_file = daily_dir / f"{yesterday_date}.md"

if daily_file.exists():
    print(f"[INFO] Daily log {yesterday_date}.md already exists. Skipping.")
    sys.exit(0)

conversation_text = get_chat_history(hours_back=24)

if not conversation_text:
    print(f"[INFO] No activities logged for {yesterday_date}.")
    with open(daily_file, "w", encoding="utf-8") as f:
        f.write(f"---\ndate: {yesterday_date}\ntype: daily\ntags: [daily, journal]\nprojects: []\n---\n\n# Daily Log: {yesterday_date}\n\nNo significant AI interactions recorded on this day.\n")
    sys.exit(0)

# Fetch known projects
known_projects = []
if projects_dir.exists():
    known_projects = [p.stem for p in projects_dir.glob("*.md")]

# Fetch existing wiki concepts & entities
wiki_index_text = ""
if wiki_index_file.exists():
    wiki_index_text = wiki_index_file.read_text(encoding="utf-8")
    if len(wiki_index_text) > 4000:
        wiki_index_text = wiki_index_text[:4000] + "\n...[truncated]"

prompt = f"""You are an autonomous Secretarial Agent maintaining an Obsidian Second Brain.
Your task is to review the following conversation log from the past 24 hours ({yesterday_date}) and write a structured Daily Journal entry.

=== KNOWN PROJECTS ===
{', '.join(known_projects) if known_projects else 'None'}

=== WIKI INDEX (Use these names for [[wikilinks]]) ===
{wiki_index_text}

=== CONVERSATION LOG ===
{conversation_text}

=== INSTRUCTIONS ===
Write a comprehensive, clean, and highly readable Markdown document that begins with YAML frontmatter:
---
date: {yesterday_date}
type: daily
tags: [daily, journal]
projects: [list of project names touched, e.g. "LAM-Cyberlab"]
summary: "One concise summary sentence of yesterday's focus"
---

# Daily Log: {yesterday_date}

## Activities & Accomplishments
(Group by project/domain. When mentioning projects, tools, or concepts that exist in the Wiki Index or Known Projects list, wrap them in [[wikilinks]]!)

## Key Decisions & Architecture
(Bullet points of technical decisions, chosen libraries, or architectural rules established)

## Unresolved Issues & Next Steps
(Bullet points of pending tasks or bugs left to solve)

DO NOT wrap the entire output in ```markdown blocks, output ONLY the raw frontmatter and markdown.
"""

print(f"[INFO] Calling Hermes AI to generate structured daily log for {yesterday_date}...")
try:
    result_text = call_hermes_api(prompt, temperature=0.2)
    
    # Strip any accidental ``` codeblock wrappers
    cleaned_text = result_text.strip()
    if cleaned_text.startswith("```markdown"):
        cleaned_text = cleaned_text[11:]
    if cleaned_text.startswith("```"):
        cleaned_text = cleaned_text[3:]
    if cleaned_text.endswith("```"):
        cleaned_text = cleaned_text[:-3]
    cleaned_text = cleaned_text.strip()
    
    with open(daily_file, "w", encoding="utf-8") as f:
        f.write(cleaned_text + "\n")
        
    print(f"[SUCCESS] Created structured daily log: {daily_file.name}")

except Exception as e:
    print(f"[ERROR] Failed to generate daily log: {e}")
    sys.exit(1)
