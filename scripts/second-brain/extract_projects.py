#!/usr/bin/env python3
"""
Project Extractor for Second Brain.
Reads yesterday's conversation logs and uses Hermes AI to extract/update project data
into the 05-Projects folder in Obsidian.
"""

import sys
import time
import json
import os

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore
from sb_utils import call_hermes_api, get_chat_history  # type: ignore

projects_dir = resolve_vault() / "05-Projects"
projects_dir.mkdir(parents=True, exist_ok=True)

conversation_text = get_chat_history(hours_back=24)
if not conversation_text:
    print("[INFO] No conversations in the last 24 hours. Exiting.")
    sys.exit(0)

# Check existing projects to provide context to AI
existing_projects = [f.name for f in projects_dir.glob("*.md")]
existing_projects_list = "\n".join(existing_projects) if existing_projects else "No existing projects."

prompt = f"""You are an autonomous Project Management Agent.
Your task is to review the following conversation log from the past 24 hours and identify if the user is discussing or working on any specific projects.

Existing projects in the vault:
{existing_projects_list}

Conversation Log:
{conversation_text}

Analyze the log. If the user worked on a project, output a JSON array of objects representing the projects updated or mentioned.
Each object must have:
- "project_name": The name of the project (e.g. "Renovasi Rumah", "Cyberlab AI"). Match existing names if applicable.
- "summary_update": A paragraph summarizing what was done or discussed regarding this project today.
- "tasks_added": A list of new tasks identified.

If NO projects were discussed, return an empty array [].
DO NOT return markdown, only raw JSON.
"""

print("[INFO] Calling Hermes AI to extract projects...")
try:
    result_text = call_hermes_api(prompt, temperature=0.1)
    projects_data = json.loads(result_text)
    
    if not projects_data:
        print("[INFO] AI determined no projects were discussed.")
        sys.exit(0)
        
    for proj in projects_data:
        p_name = proj.get("project_name", "Untitled Project").replace("/", "-")
        p_file = projects_dir / f"{p_name}.md"
        
        # Append or create
        content = f"\n## Update {time.strftime('%Y-%m-%d')}\n"
        content += f"{proj.get('summary_update', '')}\n\n"
        tasks = proj.get("tasks_added", [])
        if tasks:
            content += "### New Tasks:\n"
            for t in tasks:
                content += f"- [ ] {t}\n"
                
        if p_file.exists():
            with open(p_file, "a") as f:
                f.write(content)
            print(f"[SUCCESS] Updated project: {p_name}")
        else:
            with open(p_file, "w") as f:
                f.write(f"# {p_name}\n")
                f.write(content)
            print(f"[SUCCESS] Created new project: {p_name}")

except Exception as e:
    print(f"[ERROR] Failed to extract projects: {e}")
    sys.exit(1)
