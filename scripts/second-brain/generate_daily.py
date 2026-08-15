#!/usr/bin/env python3
"""
Daily Activity Logger for Second Brain.
Reads yesterday's conversation logs and uses Hermes AI to generate a comprehensive
daily journal summarizing all activities, decisions, and discussions.
"""

import sys
import os
from datetime import datetime, timedelta

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore
from sb_utils import call_hermes_api, get_chat_history  # type: ignore

daily_dir = resolve_vault() / "07-Daily"
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
    # Create an empty template
    with open(daily_file, "w") as f:
        f.write(f"# Daily Log: {yesterday_date}\n\nNo significant AI interactions recorded on this day.\n")
    sys.exit(0)

prompt = f"""You are an autonomous Secretarial Agent.
Your task is to review the following conversation log from the past 24 hours ({yesterday_date}) and write a Daily Journal entry for the user.

Conversation Log:
{conversation_text}

Write a comprehensive and highly readable Markdown document that summarizes:
1. What the user worked on or discussed.
2. Any major decisions made.
3. Any unresolved issues or questions left hanging.

Use a professional but friendly tone. Format it cleanly with headings (e.g. ## Activities, ## Key Decisions, ## Notes).
DO NOT wrap the entire output in ```markdown blocks, just output the raw markdown text.
Start the document with a title: # Daily Log: {yesterday_date}
"""

print(f"[INFO] Calling Hermes AI to generate daily log for {yesterday_date}...")
try:
    result_text = call_hermes_api(prompt, temperature=0.3)
    
    with open(daily_file, "w") as f:
        f.write(result_text)
        
    print(f"[SUCCESS] Created daily log: {daily_file.name}")

except Exception as e:
    print(f"[ERROR] Failed to generate daily log: {e}")
    sys.exit(1)
