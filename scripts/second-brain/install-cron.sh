#!/usr/bin/env bash
# Install scheduled jobs using Hermes cron (not Linux crontab).
# This ensures all jobs are visible in `hermes cron list` and the dashboard.

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get absolute path to the scripts
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-second-brain.sh"
SKILLS_SCRIPT="$SCRIPT_DIR/sync-skills.sh"
REFLECTION_SCRIPT="$SCRIPT_DIR/daily-reflection.sh"

# Find hermes binary
HERMES_BIN="$(which hermes 2>/dev/null || true)"
if [ -z "$HERMES_BIN" ]; then
  HERMES_BIN="$HOME/.hermes/hermes-agent/venv/bin/hermes"
fi
if [ ! -x "$HERMES_BIN" ]; then
  error "hermes binary not found. Please ensure Hermes is installed."
  exit 1
fi

info "Setting up Hermes Cron Jobs..."

# Hermes cron requires scripts to be in ~/.hermes/scripts/
# Create tiny wrapper scripts that call the real ones (avoids duplicates)
HERMES_SCRIPTS_DIR="$HOME/.hermes/scripts"
mkdir -p "$HERMES_SCRIPTS_DIR"

for script in "$SYNC_SCRIPT" "$SKILLS_SCRIPT" "$REFLECTION_SCRIPT"; do
  if [ -f "$script" ]; then
    basename_script="$(basename "$script")"
    rm -f "$HERMES_SCRIPTS_DIR/$basename_script"
    cat > "$HERMES_SCRIPTS_DIR/$basename_script" <<WRAPPER
#!/bin/bash
exec bash "$script" "\$@"
WRAPPER
    chmod +x "$HERMES_SCRIPTS_DIR/$basename_script"
  fi
done
info "Created wrapper scripts in $HERMES_SCRIPTS_DIR"

# Remove existing hermes cron jobs with matching names (to avoid duplicates)
CRON_LIST=$("$HERMES_BIN" cron list 2>/dev/null || true)
for job_name in "second-brain-sync" "skills-sync" "daily-reflection"; do
  # Parse job IDs from the multi-line output format:
  #   <id> [active]
  #     Name:      <name>
  echo "$CRON_LIST" | grep -B1 "Name:.*$job_name" | grep -oP '^\s+\K[a-f0-9]+' | while read -r job_id; do
    "$HERMES_BIN" cron remove "$job_id" 2>/dev/null && warn "Removed existing job: $job_name ($job_id)" || true
  done
done

echo

# 1. Second Brain Sync — every 12 hours
if [ -f "$SYNC_SCRIPT" ]; then
  info "Creating: Second Brain Sync (every 12 hours)..."
  "$HERMES_BIN" cron create \
    --name "second-brain-sync" \
    --script "sync-second-brain.sh" \
    --no-agent \
    "0 */12 * * *" \
    "Sync Second Brain: transcribe, parse, wiki ingest, and push to GitHub"
  success "Second Brain Sync scheduled every 12 hours!"
else
  warn "sync-second-brain.sh not found — skipping."
fi

echo

# 2. Skills Sync — every day at midnight
if [ -f "$SKILLS_SCRIPT" ]; then
  info "Creating: Skills Sync (daily at midnight)..."
  "$HERMES_BIN" cron create \
    --name "skills-sync" \
    --script "sync-skills.sh" \
    --no-agent \
    "0 0 * * *" \
    "Sync Hermes skills folder with GitHub"
  success "Skills Sync scheduled daily at midnight!"
else
  warn "sync-skills.sh not found — skipping."
fi

echo

# 3. Daily Reflection — every day at 00:05
if [ -f "$REFLECTION_SCRIPT" ]; then
  info "Creating: Daily Reflection (daily at 00:05)..."
  "$HERMES_BIN" cron create \
    --name "daily-reflection" \
    --script "daily-reflection.sh" \
    --no-agent \
    "5 0 * * *" \
    "Generate daily reflection and journal entry"
  success "Daily Reflection scheduled daily at 00:05!"
else
  warn "daily-reflection.sh not found — skipping."
fi

echo
success "All cron jobs installed! View them with: hermes cron list"
