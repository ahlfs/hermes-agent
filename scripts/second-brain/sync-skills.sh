#!/usr/bin/env bash
# sync-skills.sh — Sync your custom skills to GitHub (2-way sync)
#
# Usage:
#   bash scripts/second-brain/sync-skills.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Load env variables
HERMES_ENV="$HOME/.hermes/.env"
if [ -f "$HERMES_ENV" ]; then
  export $(grep -v '^#' "$HERMES_ENV" | grep -v '^\s*$' | xargs)
else
  warn ".env file not found at $HERMES_ENV. Cloud sync might fail."
fi

GH_USER="${GITHUB_USERNAME:-}"
GH_REPO="${GITHUB_REPO_SKILLS:-hermes-skills}"
SKILLS_DIR="$HOME/.hermes/skills"

if [ -z "$GH_USER" ]; then
  info "GITHUB_USERNAME not set in .env. Skipping cloud sync."
  exit 0
fi

mkdir -p "$SKILLS_DIR"
cd "$SKILLS_DIR"

echo
info "== Pass 0: git auto-pull =="

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REMOTE_URL="git@github.com:${GH_USER}/${GH_REPO}.git"
  info "Skills folder is not a git repo. Attempting to clone from GitHub..."
  
  # Try cloning the remote repo (preserves history)
  TEMP_CLONE="/tmp/hermes-skills-clone-$$"
  if git clone "$REMOTE_URL" "$TEMP_CLONE" 2>&1; then
    # Move .git from clone into our skills dir
    mv "$TEMP_CLONE/.git" "$SKILLS_DIR/.git"
    rm -rf "$TEMP_CLONE"
    git checkout main -- . 2>/dev/null || true
    success "Cloned existing repo from GitHub (history preserved)."
  else
    # Remote doesn't exist yet — fresh init is fine
    rm -rf "$TEMP_CLONE"
    info "Remote repo not found. Initializing fresh Git repository..."
    git init
    git branch -M main
    if ! git remote get-url origin >/dev/null 2>&1; then
      git remote add origin "$REMOTE_URL"
    fi
  fi
else
  # Already a git repo, just ensure remote is set
  if ! git remote get-url origin >/dev/null 2>&1; then
    REMOTE_URL="git@github.com:${GH_USER}/${GH_REPO}.git"
    info "Adding remote origin: $REMOTE_URL"
    git remote add origin "$REMOTE_URL"
  fi
fi

# ── Robust git helpers ─────────────────────────────────────────────────
safe_git_pull() {
  # Clean up stale rebase state that blocks future pulls
  if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
    warn "Found stale rebase state. Cleaning up..."
    git rebase --abort 2>/dev/null || true
    rm -rf .git/rebase-merge .git/rebase-apply 2>/dev/null || true
  fi

  info "Pulling latest changes from GitHub..."
  if git pull origin main --rebase --autostash 2>&1; then
    return 0
  else
    warn "Pull with rebase failed. Trying merge strategy (accept remote on conflict)..."
    git rebase --abort 2>/dev/null || true
    rm -rf .git/rebase-merge .git/rebase-apply 2>/dev/null || true
    if git pull origin main --no-rebase -X theirs 2>&1; then
      return 0
    else
      warn "Pull failed completely. Will attempt push anyway."
      return 1
    fi
  fi
}

safe_git_push() {
  info "Pushing to GitHub..."
  local push_output
  if push_output=$(git push origin main 2>&1); then
    return 0
  else
    if echo "$push_output" | grep -q "non-fast-forward\|rejected"; then
      warn "Push rejected (non-fast-forward). Pulling and retrying..."
      safe_git_pull
      if git push origin main 2>&1; then
        return 0
      fi
    fi
    warn "Push failed: $push_output"
    return 1
  fi
}

info "Pulling latest changes from GitHub..."
safe_git_pull || warn "Pull failed (maybe empty repo or conflict). Continuing anyway."

echo
info "== Pass 1: git auto-sync =="

# Ensure git author identity is set
if ! git config user.name >/dev/null; then
  git config user.name "Hermes Agent"
  git config user.email "hermes@skills.local"
fi

git add -A
if git diff --cached --quiet; then
  info "No local changes to commit."
  HAS_CHANGES=false
else
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
  git commit -m "skills-sync: $TIMESTAMP"
  HAS_CHANGES=true
fi

if [ "$HAS_CHANGES" = true ] || [ $(git rev-list HEAD...origin/main --count 2>/dev/null || echo 0) -gt 0 ]; then
  if safe_git_push; then
    success "Skills successfully synced with GitHub!"
  else
    warn "Push failed. Possible causes:"
    warn "  1. SSH key not configured"
    warn "  2. Repository '${GH_REPO}' does not exist"
    warn "  3. No internet connection"
  fi
else
  info "Skills folder is already up to date with remote."
fi
