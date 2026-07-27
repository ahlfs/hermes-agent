#!/usr/bin/env bash
# restore-from-cloud.sh — Restore Hermes Agent data from GitHub backups.
#
# This script reads your ~/.hermes/.env configuration and automatically
# pulls your backed-up Config (skills, profiles, memories) and Second Brain
# (Obsidian Vault) from their respective GitHub repositories.
#
# Usage:
#   bash scripts/second-brain/restore-from-cloud.sh
#
# Prerequisites:
#   - ~/.hermes/.env must be configured with GITHUB_USERNAME, etc.
#   - SSH access to GitHub must be set up (ssh-keygen + key added to GitHub).
set -euo pipefail

# ── Colors for output ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Pre-flight checks ───────────────────────────────────────────────────
info "Checking prerequisites..."

# Check: git installed
if ! command -v git >/dev/null 2>&1; then
  error "'git' not found. Please install it first:"
  echo "  Ubuntu/Debian: sudo apt install git"
  echo "  macOS:         brew install git"
  exit 1
fi

# ── Load environment variables ───────────────────────────────────────────
HERMES_ENV="$HOME/.hermes/.env"
if [ ! -f "$HERMES_ENV" ]; then
  error "File $HERMES_ENV not found."
  error "Make sure you have configured your .env file first (Step 4 in README)."
  exit 1
fi

info "Reading configuration from $HERMES_ENV..."
export $(grep -v '^#' "$HERMES_ENV" | grep -v '^\s*$' | xargs)

# ── Validate required variables ──────────────────────────────────────────
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPO_CONFIG="${GITHUB_REPO_CONFIG:-hermes-config}"
GITHUB_REPO_SECONDBRAIN="${GITHUB_REPO_SECONDBRAIN:-second-brain}"

if [ -z "${OBSIDIAN_VAULT_DIR:-}" ]; then
  export OBSIDIAN_VAULT_DIR="${SECOND_BRAIN_VAULT:-$HOME/obsidian/memo}"
fi

if [ -z "$GITHUB_USERNAME" ]; then
  error "GITHUB_USERNAME is not set in $HERMES_ENV."
  error "Add the following line to your .env file:"
  echo "  GITHUB_USERNAME=your_github_username"
  exit 1
fi

info "GitHub Username    : $GITHUB_USERNAME"
info "Config Repo        : $GITHUB_REPO_CONFIG"
info "Second Brain Repo  : $GITHUB_REPO_SECONDBRAIN"
info "Obsidian Vault Dir : $OBSIDIAN_VAULT_DIR"
echo

# ── Verify SSH access to GitHub ──────────────────────────────────────────
info "Checking SSH connectivity to GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  success "SSH connection to GitHub verified."
else
  warn "Could not verify SSH connection to GitHub."
  warn "Make sure your SSH key has been added to your GitHub account."
  warn "  Generate key: ssh-keygen -t ed25519"
  warn "  Add key:      Copy ~/.ssh/id_ed25519.pub to GitHub > Settings > SSH Keys"
  warn "Continuing... (will fail if SSH is not configured)"
fi
echo

# ── Restore Config (Agent Brain) ────────────────────────────────────────
REMOTE_CONFIG="git@github.com:${GITHUB_USERNAME}/${GITHUB_REPO_CONFIG}.git"
TEMP_CONFIG="$HOME/.hermes/_restore-config-tmp"

info "═══════════════════════════════════════════════════"
info "  STAGE 1: Restoring Config (Agent Brain)"
info "═══════════════════════════════════════════════════"

# Check if the remote repo actually exists / is accessible
if git ls-remote "$REMOTE_CONFIG" &>/dev/null; then
  info "Downloading config repository from $REMOTE_CONFIG..."

  # Clean up any previous temp directory
  rm -rf "$TEMP_CONFIG"
  git clone --depth 1 "$REMOTE_CONFIG" "$TEMP_CONFIG"

  # List of config items to restore
  RESTORE_ITEMS=("skills" "profiles" "config.yaml" "MEMORY.md" "SOUL.md")

  for item in "${RESTORE_ITEMS[@]}"; do
    src="$TEMP_CONFIG/$item"
    dest="$HOME/.hermes/$item"

    if [ -e "$src" ]; then
      # If it's a directory, merge it (don't delete existing items the backup doesn't have)
      if [ -d "$src" ]; then
        info "  Restoring directory: $item/"
        cp -r "$src/." "$dest/" 2>/dev/null || cp -r "$src" "$dest"
      else
        info "  Restoring file: $item"
        cp "$src" "$dest"
      fi
    else
      warn "  $item not found in backup — skipped."
    fi
  done

  # Clean up
  rm -rf "$TEMP_CONFIG"
  success "Config restored successfully!"
else
  warn "Repository $REMOTE_CONFIG is not accessible or does not exist."
  warn "Possible causes:"
  warn "  1. SSH key not configured (run: ssh-keygen -t ed25519)"
  warn "  2. Repository '${GITHUB_REPO_CONFIG}' has not been created on GitHub"
  warn "  3. GITHUB_USERNAME is incorrect in .env"
  warn "Skipping Config restoration."
fi
echo

# ── Restore Second Brain (Knowledge Base) ────────────────────────────────
REMOTE_SB="git@github.com:${GITHUB_USERNAME}/${GITHUB_REPO_SECONDBRAIN}.git"

info "═══════════════════════════════════════════════════"
info "  STAGE 2: Restoring Second Brain (Knowledge Base)"
info "═══════════════════════════════════════════════════"

if git ls-remote "$REMOTE_SB" &>/dev/null; then
  if [ -d "$OBSIDIAN_VAULT_DIR/.git" ]; then
    # Vault already exists and is a git repo — just pull latest
    info "Vault already exists and is a Git repo. Running git pull..."
    cd "$OBSIDIAN_VAULT_DIR"
    git pull origin main && success "Second Brain updated successfully!" \
      || warn "Git pull failed. There may be conflicts to resolve."
  elif [ -d "$OBSIDIAN_VAULT_DIR" ] && [ "$(ls -A "$OBSIDIAN_VAULT_DIR" 2>/dev/null)" ]; then
    # Directory exists and is not empty, but not a git repo
    warn "Directory $OBSIDIAN_VAULT_DIR already exists and is not empty, but is not a Git repo."
    warn "To avoid data loss, Second Brain restoration is skipped."
    warn "Solution: Empty or delete the directory, then run this script again."
  else
    # Directory doesn't exist or is empty — clone directly
    info "Downloading Second Brain from $REMOTE_SB..."
    mkdir -p "$(dirname "$OBSIDIAN_VAULT_DIR")"
    rm -rf "$OBSIDIAN_VAULT_DIR"  # remove empty dir if exists
    git clone "$REMOTE_SB" "$OBSIDIAN_VAULT_DIR"
    success "Second Brain restored to $OBSIDIAN_VAULT_DIR!"
  fi
else
  warn "Repository $REMOTE_SB is not accessible or does not exist."
  warn "Possible causes:"
  warn "  1. SSH key not configured (run: ssh-keygen -t ed25519)"
  warn "  2. Repository '${GITHUB_REPO_SECONDBRAIN}' has not been created on GitHub"
  warn "  3. GITHUB_USERNAME is incorrect in .env"
  warn "Skipping Second Brain restoration."
fi
echo

# ── Summary ──────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════"
success "Restoration process complete!"
echo "═══════════════════════════════════════════════════"
echo
info "Next steps:"
echo "  1. Reload your shell:  source ~/.bashrc"
echo "  2. Start the agent:    hermes"
echo "  3. Verify agent memory by asking:"
echo "     \"What do you remember about me?\""
echo
