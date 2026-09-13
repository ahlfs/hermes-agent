#!/usr/bin/env python3
"""
Autonomous Knowledge Extractor & Selective Researcher for Second Brain.
Reads yesterday's Daily Journal, extracts newly discovered architectural concepts,
libraries, and techniques, optionally researches knowledge gaps via web tool (capped),
and writes synthesized notes to 03-Notes/Extracted-Docs/ to trigger wiki_ingest.py.
"""

import sys
import os
import json
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore
from sb_utils import call_hermes_api  # type: ignore

vault_dir = resolve_vault()
daily_dir = vault_dir / "07-Daily"
extracted_docs_dir = vault_dir / "03-Notes" / "Extracted-Docs"
wiki_index_file = vault_dir / "04-Wiki" / "index.md"
wiki_ingest_script = Path(__file__).parent / "wiki_ingest.py"

extracted_docs_dir.mkdir(parents=True, exist_ok=True)

# Read yesterday's journal
yesterday_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
daily_file = daily_dir / f"{yesterday_date}.md"

if not daily_file.exists():
    print(f"[INFO] No daily log found for {yesterday_date}. Skipping knowledge extraction.")
    sys.exit(0)

daily_content = daily_file.read_text(encoding="utf-8")
if len(daily_content) > 6000:
    daily_content = daily_content[:6000] + "\n...[truncated]"

# Fetch existing wiki index to prevent duplicate topics
existing_wiki_topics = []
if wiki_index_file.exists():
    for line in wiki_index_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("- [[") and "]]" in line:
            topic = line.split("[[")[1].split("]]")[0].strip()
            existing_wiki_topics.append(topic.lower())

wiki_topics_summary = ", ".join(existing_wiki_topics[:100])

# Phase 1: Extract concepts & identify knowledge gaps
extract_prompt = f"""You are the Chief Knowledge Engineer for an autonomous Second Brain.
Review yesterday's Daily Log ({yesterday_date}) and extract new technical concepts, architecture patterns, or tools discussed that are NOT yet documented in the Wiki.

=== EXISTING WIKI TOPICS (DO NOT DUPLICATE THESE) ===
{wiki_topics_summary}

=== DAILY LOG ===
{daily_content}

=== OUTPUT FORMAT ===
Output a JSON array of candidate knowledge topics:
[
  {{
    "title": "Clear Topic Title (e.g. D3 Force Simulation Physics, Vite Bundle Optimization)",
    "type": "concept" OR "entity",
    "category": "e.g. Frontend Architecture, Systems, Security, Database",
    "summary": "Brief summary of what was learned from the day's work",
    "needs_web_research": true OR false,
    "research_query": "Specific technical search query if deep research is needed, else empty string",
    "preliminary_notes": "Detailed technical explanation based purely on the conversation and decisions made"
  }}
]

Criteria for "needs_web_research":
- Set true ONLY if the topic involves an external standard, protocol, or library where online best practices or deep specs would elevate the knowledge quality.
- Cap: Maximum 2 topics can have needs_web_research: true.
- If no substantial technical topics were discussed, return [].

Output ONLY raw JSON array.
"""

print("[INFO] Calling AI to identify new knowledge concepts from Daily Log...")
try:
    resp = call_hermes_api(extract_prompt, temperature=0.1)
    cleaned = resp.strip()
    if cleaned.startswith("```json"):
        cleaned = cleaned[7:]
    if cleaned.startswith("```"):
        cleaned = cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]
    cleaned = cleaned.strip()

    candidates = json.loads(cleaned)
    if not isinstance(candidates, list) or not candidates:
        print("[INFO] No new technical concepts identified for knowledge synthesis today.")
        sys.exit(0)

    print(f"[INFO] Found {len(candidates)} candidate knowledge topic(s).")
    
    research_count = 0
    written_notes = 0

    for item in candidates:
        title = item.get("title", "").replace("/", "-").strip()
        if not title:
            continue
            
        if title.lower() in existing_wiki_topics:
            print(f"[SKIP] Topic '{title}' already exists in Wiki index.")
            continue

        needs_research = item.get("needs_web_research", False)
        research_query = item.get("research_query", "")
        body_content = item.get("preliminary_notes", "")
        category = item.get("category", "Technology")
        k_type = item.get("type", "concept")

        # Selective Web Research (Max 2 queries)
        if needs_research and research_query and research_count < 2:
            print(f"[RESEARCH] Performing deep web research for: {title} ('{research_query}')...")
            research_prompt = f"""Conduct focused research on: {research_query}.
Provide a clean, comprehensive markdown summary explaining the architecture, key mechanics, and industry best practices."""
            try:
                web_cmd = ["hermes", "-z", research_prompt, "-t", "web", "--yolo"]
                web_res = subprocess.run(web_cmd, capture_output=True, text=True, timeout=120)
                if web_res.returncode == 0 and web_res.stdout.strip():
                    body_content += f"\n\n## Extended Research & Best Practices\n{web_res.stdout.strip()}"
                    research_count += 1
            except Exception as e:
                print(f"[WARN] Web research failed for {title}: {e}")

        # Assemble Note for Extracted-Docs
        note_filename = f"{yesterday_date}_{title.replace(' ', '-')}.md"
        note_path = extracted_docs_dir / note_filename
        
        note_markdown = f"""---
title: {title}
type: {k_type}
category: {category}
tags: [knowledge-extraction, {category.lower().replace(' ', '-')}]
source_daily: [[{yesterday_date}]]
extracted_date: {datetime.now().strftime('%Y-%m-%d')}
---

# {title}

## Summary
{item.get('summary', '')}

## Technical Insights & Practical Implementation
{body_content}
"""
        note_path.write_text(note_markdown, encoding="utf-8")
        print(f"[SUCCESS] Wrote knowledge note: {note_filename}")
        written_notes += 1

    # Trigger wiki_ingest.py if new notes were generated
    if written_notes > 0 and wiki_ingest_script.exists():
        print(f"[INFO] Ingesting {written_notes} new note(s) into 04-Wiki/...")
        subprocess.run([sys.executable, str(wiki_ingest_script)], check=False)

except Exception as e:
    print(f"[ERROR] Failed knowledge extraction pipeline: {e}")
    sys.exit(1)
