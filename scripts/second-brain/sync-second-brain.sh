#!/usr/bin/env bash
# AI Second Brain — sync automation (Hermes Agent edition).
#
# Passes, in order:
#   1. transcribe audio        -> 03-Notes/Transcripts/
#   2. parse documents         -> 03-Notes/Extracted-Docs/
#   3. consolidate to memory   -> Hermes MEMORY.md/USER.md (read every session)
#   4. build the wiki          -> 04-Wiki/ (interlinked entity/concept pages)
#   4.5 lint the wiki          -> 04-Wiki/lint-report.md
#
# Run this whenever new raw files land in the vault's 01-Audio/ or
# 02-Documents/ (default vault: ~/obsidian/memo).
#
# This script is owned by hermes-agent (the Absolute Owner of Second Brain).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load env from ~/.hermes/.env if present
HERMES_ENV="$HOME/.hermes/.env"
if [ -f "$HERMES_ENV" ]; then
  export $(grep -v '^#' "$HERMES_ENV" | grep -v '^\s*$' | xargs)
fi

# Harmonize env vars: OBSIDIAN_VAULT_DIR is canonical (from PRD),
# SECOND_BRAIN_VAULT is legacy fallback.
if [ -z "${OBSIDIAN_VAULT_DIR:-}" ]; then
  export OBSIDIAN_VAULT_DIR="${SECOND_BRAIN_VAULT:-$HOME/obsidian/memo}"
fi
# Also set SECOND_BRAIN_VAULT for backward compat with any external tool
export SECOND_BRAIN_VAULT="$OBSIDIAN_VAULT_DIR"

# Find Python — prefer the second-brain venv, fall back to system python3
VENV_PYTHON="$HOME/.hermes/venv-second-brain/bin/python"
if [ ! -x "$VENV_PYTHON" ]; then
  # Try the lam-cyberlab venv as second fallback
  VENV_PYTHON="$HOME/lam-cyberlab/.venv-second-brain/bin/python"
fi
if [ ! -x "$VENV_PYTHON" ]; then
  echo "Second-brain venv not found. Set it up first:" >&2
  echo "  bash $SCRIPT_DIR/setup-venv.sh" >&2
  exit 1
fi

echo "== Pass 1: audio transcription =="
"$VENV_PYTHON" "$SCRIPT_DIR/ingest_audio.py"

echo
echo "== Pass 2: document parsing =="
"$VENV_PYTHON" "$SCRIPT_DIR/ingest_docs.py"

echo
echo "== Pass 3: memory consolidation =="
if command -v hermes >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/consolidate_memory.py"
else
  echo "hermes CLI not found on PATH — skipping memory consolidation." >&2
fi

echo
echo "== Pass 4: wiki ingest =="
if command -v hermes >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/wiki_ingest.py"
else
  echo "hermes CLI not found on PATH — skipping wiki ingest." >&2
fi

echo
echo "== Pass 4.5: wiki lint =="
python3 "$SCRIPT_DIR/wiki_lint.py" --no-llm --save-report || true

# cleanup moved to after git push (Pass 7) to ensure backup exists

echo
echo "== Pass 6: git auto-sync =="
cd "$OBSIDIAN_VAULT_DIR"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Auto-setup remote dari env vars jika belum ada
  GH_USER="${GITHUB_USERNAME:-}"
  GH_REPO="${GITHUB_REPO_SECONDBRAIN:-second-brain}"
  if [ -n "$GH_USER" ] && ! git remote get-url origin >/dev/null 2>&1; then
    REMOTE_URL="git@github.com:${GH_USER}/${GH_REPO}.git"
    echo "Menambahkan remote origin: $REMOTE_URL"
    git remote add origin "$REMOTE_URL"
  fi

  git add -A
  if git diff --cached --quiet; then
    echo "Tidak ada perubahan baru. Skip push."
  else
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
    git commit -m "knowledge-sync: $TIMESTAMP"
    git push origin main && echo "Knowledge berhasil di-push ke GitHub!" \
      || echo "Push gagal (mungkin offline). Commit tersimpan lokal."
  fi
else
  echo "Vault belum di-init sebagai Git repo. Skip auto-sync."
  echo "Jalankan: cd ~/obsidian/memo && git init && git remote add origin <url>"
fi

echo "Second brain sync complete."

echo
echo "== Pass 7: cleanup source notes and raw files =="
echo "(runs after git push to ensure cloud backup exists)"
python3 "$SCRIPT_DIR/cleanup_sources.py" || true

echo
echo "All passes complete."
