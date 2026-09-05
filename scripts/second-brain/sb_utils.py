"""Shared utilities for Second Brain automation scripts."""
import sys
import os
import sqlite3
import time
import requests
from pathlib import Path

# Fix local imports for IDE/LSP
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _vault import resolve_vault  # type: ignore

def get_hermes_env():
    """Load env variables from ~/.hermes/.env and return api_key and port."""
    env_path = Path.home() / ".hermes" / ".env"
    api_key = ""
    port = "8642" # Default Hermes API port
    
    if env_path.exists():
        with open(env_path, "r") as f:
            for line in f:
                if line.startswith("API_SERVER_KEY="):
                    api_key = line.split("=")[1].strip()
                elif line.startswith("API_SERVER_PORT="):
                    port = line.split("=")[1].strip()
    return api_key, port

def call_hermes_api(prompt: str, temperature: float = 0.3, timeout: int = 120) -> str:
    """Send a prompt to the local Hermes API and return the response text."""
    api_key, port = get_hermes_env()
    url = f"http://localhost:{port}/v1/chat/completions"
    
    response = requests.post(
        url,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={
            "model": "auto",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": temperature
        },
        timeout=timeout
    )
    response.raise_for_status()
    result_text = response.json()["choices"][0]["message"]["content"].strip()
    
    # Clean up json/markdown wrapping if present
    if result_text.startswith("```json"):
        result_text = result_text[7:-3].strip()
    elif result_text.startswith("```markdown"):
        result_text = result_text[11:-3].strip()
    elif result_text.startswith("```"):
        result_text = result_text[3:-3].strip()
        
    return result_text

def get_chat_history(hours_back: int = 24, truncate_len: int = 1000) -> str:
    """Fetch recent chat history from Hermes state.db, optimized for tokens."""
    db_path = Path.home() / ".hermes" / "state.db"
    if not db_path.exists():
        return ""
        
    now = time.time()
    start_ts = now - (hours_back * 3600)
    
    # Try with timeout to avoid 'database is locked' crashes
    conn = sqlite3.connect(db_path, timeout=10.0)
    cur = conn.cursor()
    # Basic keyword filtering to save tokens - only grab messages containing actionable/project words, 
    # OR just grab all user/assistant messages if we want a full summary. 
    # For now, we grab all but rely on truncate_len to save tokens.
    cur.execute(
        "SELECT role, content FROM messages WHERE timestamp >= ? AND timestamp <= ? AND role IN ('user', 'assistant') ORDER BY timestamp ASC",
        (start_ts, now)
    )
    rows = cur.fetchall()
    conn.close()

    conversation_text = ""
    for role, content in rows:
        if content:
            # Truncate very long messages to save context window
            text = content[:truncate_len]
            if len(content) > truncate_len:
                text += "..."
            conversation_text += f"{role.upper()}: {text}\n"
            
    return conversation_text.strip()
