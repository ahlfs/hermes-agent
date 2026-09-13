#!/usr/bin/env python3
"""
Autonomous Self-Reflection Script for Second Brain.
Reads yesterday's Daily Log, asks Hermes Agent via the official memory tool
to synthesize durable facts and learnings, preventing raw string pollution.
"""

import sys
import os
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore

daily_dir = resolve_vault() / "07-Daily"

# Read yesterday's journal
yesterday_date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')
daily_file = daily_dir / f"{yesterday_date}.md"

if not daily_file.exists():
    print(f"[INFO] No daily log found for {yesterday_date}. Skipping reflection.")
    sys.exit(0)

daily_content = daily_file.read_text(encoding="utf-8")
if len(daily_content) > 6000:
    daily_content = daily_content[:6000] + "\n...[truncated]"

prompt = f"""Read this Daily Log from yesterday ({yesterday_date}) for Second Brain reflection:

{daily_content}

Your goal:
1. Identify any durable facts, permanent user preferences, or stable environment conventions discovered.
2. Filter out all transient errors (e.g. 404s, temporary timeouts, temporary debugging logs, raw stack traces).
3. If there are durable facts worth remembering, save them using the memory tool.
4. If nothing is worth permanent memory storage, perform no memory actions and output 'NO_DURABLE_MEMORY'.
"""

print(f"[INFO] Calling Hermes CLI with memory tool for {yesterday_date}...")
cmd = ["hermes", "-z", prompt, "-t", "memory", "--yolo"]

try:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    if result.returncode == 0:
        print("[SUCCESS] Self-reflection processed cleanly through Hermes memory subsystem.")
        print(result.stdout.strip()[:300])
    else:
        print(f"[WARN] Hermes memory consolidation exited with code {result.returncode}: {result.stderr.strip()[:200]}")
except Exception as e:
    print(f"[ERROR] Failed to run self-reflection memory tool: {e}")
    sys.exit(1)
