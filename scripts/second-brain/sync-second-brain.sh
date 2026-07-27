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

# ── Colors ───────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Pre-flight checks ───────────────────────────────────────────────────
info "Checking prerequisites..."

# Check: git installed
if ! command -v git >/dev/null 2>&1; then
  error "'git' not found. Please install it first:"
  echo "  Ubuntu/Debian: sudo apt install git"
  echo "  macOS:         brew install git"
  exit 1
fi

# Check: ffmpeg installed (needed for audio transcription)
if ! command -v ffmpeg >/dev/null 2>&1; then
  warn "'ffmpeg' not found. Pass 1 (audio transcription) will fail."
  warn "Install with: sudo apt install ffmpeg  (or: brew install ffmpeg)"
fi

# Check: tesseract installed (needed for OCR)
if ! command -v tesseract >/dev/null 2>&1; then
  warn "'tesseract' not found. Pass 2 (image OCR) may be limited."
  warn "Install with: sudo apt install tesseract-ocr  (or: brew install tesseract)"
fi

# Load env from ~/.hermes/.env if present
HERMES_ENV="$HOME/.hermes/.env"
if [ -f "$HERMES_ENV" ]; then
  export $(grep -v '^#' "$HERMES_ENV" | grep -v '^\s*$' | xargs)
else
  warn "$HERMES_ENV not found. Using default values."
  warn "Create a .env file with OBSIDIAN_VAULT_DIR for best results."
fi

# Harmonize env vars: OBSIDIAN_VAULT_DIR is canonical (from PRD),
# SECOND_BRAIN_VAULT is legacy fallback.
if [ -z "${OBSIDIAN_VAULT_DIR:-}" ]; then
  export OBSIDIAN_VAULT_DIR="${SECOND_BRAIN_VAULT:-$HOME/obsidian/memo}"
  warn "OBSIDIAN_VAULT_DIR not set. Using default: $OBSIDIAN_VAULT_DIR"
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
  error "Second-brain venv not found. Please run setup first:"
  echo "  cd ~/.hermes/hermes-agent"
  echo "  bash scripts/second-brain/setup-venv.sh"
  exit 1
fi

success "All prerequisites met."
info "Vault: $OBSIDIAN_VAULT_DIR"
info "Python: $VENV_PYTHON"
echo

# Auto-initialize Second Brain folder structure
mkdir -p "$OBSIDIAN_VAULT_DIR/01-Audio"
mkdir -p "$OBSIDIAN_VAULT_DIR/02-Documents"
mkdir -p "$OBSIDIAN_VAULT_DIR/03-Notes/Transcripts"
mkdir -p "$OBSIDIAN_VAULT_DIR/03-Notes/Extracted-Docs"
mkdir -p "$OBSIDIAN_VAULT_DIR/04-Wiki"
mkdir -p "$OBSIDIAN_VAULT_DIR/05-Projects"
mkdir -p "$OBSIDIAN_VAULT_DIR/06-Tasks"
mkdir -p "$OBSIDIAN_VAULT_DIR/07-Daily"

SCHEMA_FILE="$OBSIDIAN_VAULT_DIR/WIKI_SCHEMA.md"
if [ ! -f "$SCHEMA_FILE" ]; then
  info "Copying default WIKI_SCHEMA.md to vault..."
  if [ -f "$SCRIPT_DIR/templates/WIKI_SCHEMA.md" ]; then
    cp "$SCRIPT_DIR/templates/WIKI_SCHEMA.md" "$SCHEMA_FILE"
  fi
fi

echo
info "== Pass 1: audio transcription =="
"$VENV_PYTHON" "$SCRIPT_DIR/ingest_audio.py" || warn "Pass 1 failed. Check if 'ffmpeg' is installed."

echo
info "== Pass 2: document parsing =="
"$VENV_PYTHON" "$SCRIPT_DIR/ingest_docs.py" || warn "Pass 2 failed. Check if 'tesseract' is installed."

echo
info "== Pass 3: memory consolidation =="
if command -v hermes >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/consolidate_memory.py" || warn "Pass 3 failed."
else
  warn "hermes CLI not found on PATH — skipping memory consolidation."
fi

echo
info "== Pass 4: wiki ingest =="
if command -v hermes >/dev/null 2>&1; then
  python3 "$SCRIPT_DIR/wiki_ingest.py" || warn "Pass 4 failed."
else
  warn "hermes CLI not found on PATH — skipping wiki ingest."
fi

echo
info "== Pass 4.5: wiki lint =="
python3 "$SCRIPT_DIR/wiki_lint.py" --no-llm --save-report || true

# cleanup moved to after git push (Pass 7) to ensure backup exists

echo
info "== Pass 6: git auto-sync =="
cd "$OBSIDIAN_VAULT_DIR"

GH_USER="${GITHUB_USERNAME:-}"
GH_REPO="${GITHUB_REPO_SECONDBRAIN:-second-brain}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$GH_USER" ]; then
    info "Initializing Vault as a Git repository..."
    git init
    git branch -M main
  else
    warn "Vault is not initialized as a Git repo. Skipping auto-sync."
    warn "To enable, configure GITHUB_USERNAME in ~/.hermes/.env or run manually:"
    echo "  cd $OBSIDIAN_VAULT_DIR && git init && git remote add origin <url>"
  fi
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$GH_USER" ] && ! git remote get-url origin >/dev/null 2>&1; then
    REMOTE_URL="git@github.com:${GH_USER}/${GH_REPO}.git"
    info "Adding remote origin: $REMOTE_URL"
    git remote add origin "$REMOTE_URL"
  fi

  # Ensure git author identity is set so commits don't fail
  if ! git config user.name >/dev/null; then
    git config user.name "Hermes Agent"
    git config user.email "hermes@secondbrain.local"
  fi

  git add -A
  if git diff --cached --quiet; then
    info "No local changes to commit."
    HAS_CHANGES=false
  else
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
    git commit -m "knowledge-sync: $TIMESTAMP"
    HAS_CHANGES=true
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    info "Pulling latest changes from GitHub..."
    git pull origin main --rebase --autostash || warn "Pull failed or conflict occurred."

    if [ "$HAS_CHANGES" = true ] || [ $(git rev-list HEAD...origin/main --count 2>/dev/null || echo 0) -gt 0 ]; then
      info "Pushing to GitHub..."
      if git push origin main 2>/dev/null; then
        success "Knowledge successfully synced with GitHub!"
      else
        warn "Push failed. Possible causes:"
        warn "  1. SSH key not configured (run: ssh-keygen -t ed25519)"
        warn "  2. Repository '${GH_REPO}' does not exist on GitHub"
        warn "  3. No internet connection"
      fi
    else
      info "Vault is already up to date with remote."
    fi
  fi
fi

echo
success "Second brain sync complete."

echo
info "== Pass 7: cleanup source notes and raw files =="
info "(runs after git push to ensure cloud backup exists)"
python3 "$SCRIPT_DIR/cleanup_sources.py" || true

echo
success "All passes complete!"
