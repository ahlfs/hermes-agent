#!/usr/bin/env bash
# AI Second Brain — Daily Reflection & Project Extraction Cron Job
#
# This script runs ONCE a day (e.g. 06:00 AM) to:
#   1. Extract project updates from yesterday's chat logs -> 05-Projects/
#   2. Generate a daily journal summarizing yesterday -> 07-Daily/
#   3. Trigger AI self-reflection to learn from yesterday -> MEMORY.md
#
# Unlike sync-second-brain.sh, this script is decoupled so it doesn't
# run every time a new document is dropped into the vault.

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

# Find Python — prefer the second-brain venv, fall back to system python3
VENV_PYTHON="$HOME/.hermes/venv-second-brain/bin/python"
if [ ! -x "$VENV_PYTHON" ]; then
  # Try the lam-cyberlab venv as second fallback
  VENV_PYTHON="$HOME/lam-cyberlab/.venv-second-brain/bin/python"
fi
if [ ! -x "$VENV_PYTHON" ]; then
  # Final fallback
  VENV_PYTHON="python3"
fi

info "Starting Daily Reflection & Project Extractor Pipeline..."
echo

info "== Step 1: Project Extraction =="
"$VENV_PYTHON" "$SCRIPT_DIR/extract_projects.py" || warn "Project Extraction failed."
echo

info "== Step 2: Daily Journal Generation =="
"$VENV_PYTHON" "$SCRIPT_DIR/generate_daily.py" || warn "Daily Journal Generation failed."
echo

info "== Step 3: Autonomous Self-Reflection =="
"$VENV_PYTHON" "$SCRIPT_DIR/self_reflection.py" || warn "Self-Reflection failed."
echo

success "Daily Reflection Pipeline Complete! Your Second Brain is now smarter."
