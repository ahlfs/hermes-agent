#!/usr/bin/env python3
"""
Autonomous Self-Reflection Script for Second Brain.
Reads yesterday's Daily Log, asks the AI to reflect on its own performance/activities,
and updates the core MEMORY.md with new insights and learning goals.
"""

import sys
import os
from datetime import datetime, timedelta
from pathlib import Path

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore
from sb_utils import call_hermes_api  # type: ignore

daily_dir = resolve_vault() / "07-Daily"
memory_file = Path.home() / ".hermes" / "memories" / "MEMORY.md"
memory_file.parent.mkdir(parents=True, exist_ok=True)

# Read yesterday's journal
yesterday_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
daily_file = daily_dir / f"{yesterday_date}.md"

if not daily_file.exists():
    print(f"[INFO] No daily log found for {yesterday_date}. Skipping reflection.")
    sys.exit(0)

with open(daily_file, "r") as f:
    daily_content = f.read()

prompt = f"""You are an autonomous AI Agent reflecting on your past day's performance.

Here is the daily log of what you and the user did yesterday ({yesterday_date}):
{daily_content}

Your task:
1. Reflect on what was discussed. Identify any knowledge gaps, repeated mistakes, or new preferences the user demonstrated.
2. Based on this reflection, write a short, concise "Lesson Learned" or "New Rule" that you should add to your permanent memory to serve the user better in the future.
3. Formulate the new rule as a direct instruction to yourself (e.g., "Always remember to...", "The user prefers...").

If nothing significant happened that warrants a new rule, just output "NO_REFLECTION_NEEDED".
Otherwise, output ONLY the text of the new rule(s). DO NOT wrap in markdown code blocks.
"""

print(f"[INFO] Calling Hermes AI to self-reflect on {yesterday_date}...")
try:
    result_text = call_hermes_api(prompt, temperature=0.4)
    
    if result_text == "NO_REFLECTION_NEEDED" or "NO_REFLECTION_NEEDED" in result_text:
        print("[INFO] AI decided no reflection/new rule is needed today.")
        sys.exit(0)
        
    # Append to MEMORY.md
    print(f"[SUCCESS] AI formulated new rule: {result_text[:50]}...")
    
    append_str = f"\n\n### Self-Reflection ({yesterday_date})\n{result_text}\n"
    
    with open(memory_file, "a") as f:
        f.write(append_str)
        
    print(f"[SUCCESS] Updated MEMORY.md")

except Exception as e:
    print(f"[ERROR] Failed to run self-reflection: {e}")
    sys.exit(1)
