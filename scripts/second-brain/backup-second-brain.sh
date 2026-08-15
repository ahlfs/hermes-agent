#!/usr/bin/env bash
# AI Second Brain — Cloud Backup & Cleanup Pipeline.
#
# This script is decoupled from local ingestion (sync-second-brain.sh).
# It runs periodically (e.g. via cron at midnight) to:
#   1. Auto-pull latest changes from GitHub
#   2. Commit and push local Second Brain updates
#   3. Clean up large raw files (audio/pdfs) ONLY IF push succeeds.

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

# Load env from ~/.hermes/.env if present
HERMES_ENV="$HOME/.hermes/.env"
if [ -f "$HERMES_ENV" ]; then
  export $(grep -v '^#' "$HERMES_ENV" | grep -v '^\s*$' | xargs)
fi

if [ -z "${OBSIDIAN_VAULT_DIR:-}" ]; then
  export OBSIDIAN_VAULT_DIR="${SECOND_BRAIN_VAULT:-$HOME/obsidian/memo}"
fi
export SECOND_BRAIN_VAULT="$OBSIDIAN_VAULT_DIR"

# Find Python
VENV_PYTHON="$HOME/.hermes/venv-second-brain/bin/python"
if [ ! -x "$VENV_PYTHON" ]; then
  VENV_PYTHON="$HOME/lam-cyberlab/.venv-second-brain/bin/python"
fi
if [ ! -x "$VENV_PYTHON" ]; then
  VENV_PYTHON="python3"
fi

info "Starting Second Brain Cloud Backup Pipeline..."
info "Vault: $OBSIDIAN_VAULT_DIR"

cd "$OBSIDIAN_VAULT_DIR"
GH_USER="${GITHUB_USERNAME:-}"
GH_REPO="${GITHUB_REPO_SECONDBRAIN:-second-brain}"

if [ -z "$GH_USER" ]; then
  warn "GITHUB_USERNAME not set in .env — cloud backup is disabled."
  exit 0
fi

echo
info "== Pre-Flight: Initializing Git Repo =="
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  info "Initializing Vault as a Git repository..."
  git init
  git branch -M main
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  REMOTE_URL="git@github.com:${GH_USER}/${GH_REPO}.git"
  info "Adding remote origin: $REMOTE_URL"
  git remote add origin "$REMOTE_URL"
fi

# Ensure git author identity is set
if ! git config user.name >/dev/null; then
  git config user.name "Hermes Agent"
  git config user.email "hermes@secondbrain.local"
fi

echo
info "== Pass 0: git auto-pull =="
info "Pulling latest changes from GitHub..."
git pull origin main --rebase --autostash || warn "Pull failed (maybe empty repo or conflict). Continuing anyway."

echo
info "== Pass 6: git push =="
git add -A
if git diff --cached --quiet; then
  info "No local changes to commit."
  HAS_CHANGES=false
else
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
  git commit -m "knowledge-backup: $TIMESTAMP"
  HAS_CHANGES=true
fi

PUSH_SUCCESS=false
if [ "$HAS_CHANGES" = true ] || [ $(git rev-list HEAD...origin/main --count 2>/dev/null || echo 0) -gt 0 ]; then
  info "Pushing to GitHub..."
  if git push origin main 2>/dev/null; then
    success "Knowledge successfully synced with GitHub!"
    PUSH_SUCCESS=true
  else
    warn "Push failed. Cleanup will be skipped to protect your local files."
  fi
else
  info "Vault is already up to date with remote."
  PUSH_SUCCESS=true
fi

echo
if [ "$PUSH_SUCCESS" = true ]; then
  info "== Pass 7: cleanup source notes and raw files =="
  info "(Running cleanup because cloud backup is verified safe)"
  "$VENV_PYTHON" "$SCRIPT_DIR/cleanup_sources.py" || warn "Cleanup script encountered an error."
  success "Backup and Cleanup complete!"
else
  warn "Skipping Pass 7 (cleanup) due to backup failure."
fi
