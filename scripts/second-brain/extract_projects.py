#!/usr/bin/env python3
"""
Project Extractor for Second Brain.
Reads yesterday's conversation logs and uses Hermes AI to extract/update project data
into the 05-Projects folder in Obsidian with full frontmatter and wikilinks.
"""

import sys
import time
import json
import os
from pathlib import Path

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore
from sb_utils import call_hermes_api, get_chat_history  # type: ignore

vault_dir = resolve_vault()
projects_dir = vault_dir / "05-Projects"
wiki_index_file = vault_dir / "04-Wiki" / "index.md"
projects_dir.mkdir(parents=True, exist_ok=True)

conversation_text = get_chat_history(hours_back=24)
if not conversation_text:
    print("[INFO] No conversations in the last 24 hours. Exiting.")
    sys.exit(0)

# Check existing projects to provide context to AI
existing_projects = [f.stem for f in projects_dir.glob("*.md")]
existing_projects_list = "\n".join(f"- {p}" for p in existing_projects) if existing_projects else "No existing projects."

wiki_index_text = ""
if wiki_index_file.exists():
    wiki_index_text = wiki_index_file.read_text(encoding="utf-8")
    if len(wiki_index_text) > 3000:
        wiki_index_text = wiki_index_text[:3000] + "\n...[truncated]"

prompt = f"""You are an autonomous Project Management Agent for an Obsidian Second Brain.
Your task is to review the conversation log from the past 24 hours and identify if the user is working on or discussing specific software/hardware/business projects.

=== EXISTING PROJECTS ===
{existing_projects_list}

=== WIKI CONCEPTS (Use these for [[wikilinks]]) ===
{wiki_index_text}

=== CONVERSATION LOG ===
{conversation_text}

=== OUTPUT REQUIREMENTS ===
Output a JSON array of objects representing projects updated or created.
Each object must have:
- "project_name": The standardized name of the project (e.g. "LAM-Cyberlab", "LAM-Router", "Project-CDE-PUPR"). Match existing names if applicable.
- "project_type": e.g. "web-app", "ai-infrastructure", "system-service", "mobile-app"
- "tags": ["project", "tag1", "tag2"]
- "summary_update": A detailed paragraph summarizing what was built, fixed, or architected today. Wrap known tools, architectures, and concepts in [[wikilinks]].
- "tasks_added": A list of pending tasks or next action items identified.

If NO projects were discussed, return an empty array [].
DO NOT return markdown code fences, return ONLY the raw JSON array.
"""

print("[INFO] Calling Hermes AI to extract structured projects...")
try:
    result_text = call_hermes_api(prompt, temperature=0.1)
    
    # Strip potential fences
    cleaned = result_text.strip()
    if cleaned.startswith("```json"):
        cleaned = cleaned[7:]
    if cleaned.startswith("```"):
        cleaned = cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]
    cleaned = cleaned.strip()

    projects_data = json.loads(cleaned)
    
    if not isinstance(projects_data, list) or not projects_data:
        print("[INFO] AI determined no projects were discussed.")
        sys.exit(0)
        
    today = time.strftime('%Y-%m-%d')

    for proj in projects_data:
        p_name = proj.get("project_name", "Untitled-Project").replace("/", "-").strip()
        p_file = projects_dir / f"{p_name}.md"
        p_type = proj.get("project_type", "software-engineering")
        tags = proj.get("tags") or ["project"]
        if "project" not in tags:
            tags.insert(0, "project")
        tag_str = ", ".join(tags)
        
        summary_update = proj.get("summary_update", "").strip()
        tasks = proj.get("tasks_added", [])
        
        update_block = f"\n## Update {today}\n{summary_update}\n\n"
        if tasks:
            update_block += "### Tasks:\n"
            for t in tasks:
                update_block += f"- [ ] {t}\n"
            update_block += "\n"
                
        if p_file.exists():
            existing_content = p_file.read_text(encoding="utf-8")
            # If no frontmatter exists on old file, prepend frontmatter
            if not existing_content.startswith("---"):
                fm = f"---\ntitle: {p_name}\nstatus: active\ntype: {p_type}\ntags: [{tag_str}]\nupdated: {today}\n---\n\n"
                p_file.write_text(fm + existing_content + update_block, encoding="utf-8")
            else:
                with open(p_file, "a", encoding="utf-8") as f:
                    f.write(update_block)
            print(f"[SUCCESS] Updated project: {p_name}")
        else:
            fm = f"---\ntitle: {p_name}\nstatus: active\ntype: {p_type}\nstarted: {today}\nupdated: {today}\ntags: [{tag_str}]\n---\n\n"
            header = f"# {p_name}\n"
            p_file.write_text(fm + header + update_block, encoding="utf-8")
            print(f"[SUCCESS] Created new project: {p_name}")

except Exception as e:
    print(f"[ERROR] Failed to extract projects: {e}")
    sys.exit(1)
