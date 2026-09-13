#!/usr/bin/env bash
# AI Second Brain — Daily Reflection & Knowledge Compounding Pipeline
#
# This script runs ONCE a day (e.g. 06:00 AM / Midnight) to:
#   1. Extract project updates from yesterday's chat logs -> 05-Projects/
#   2. Generate a structured daily journal -> 07-Daily/
#   3. Trigger AI self-reflection via Hermes memory subsystem -> MEMORY.md
#   4. Extract newly discussed concepts & selective web research -> 04-Wiki/
#   5. Run wiki_lint quality assurance check -> 04-Wiki/lint-report.md

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
  VENV_PYTHON="$HOME/lam-cyberlab/.venv-second-brain/bin/python"
fi
if [ ! -x "$VENV_PYTHON" ]; then
  VENV_PYTHON="python3"
fi

info "Starting Daily Reflection & Autonomous Learning Pipeline..."
echo

info "== Step 1: Structured Project Extraction =="
"$VENV_PYTHON" "$SCRIPT_DIR/extract_projects.py" || warn "Project Extraction had warnings."
echo

info "== Step 2: Structured Daily Journal Generation =="
"$VENV_PYTHON" "$SCRIPT_DIR/generate_daily.py" || warn "Daily Journal Generation had warnings."
echo

info "== Step 3: Clean Autonomous Self-Reflection =="
"$VENV_PYTHON" "$SCRIPT_DIR/self_reflection.py" || warn "Self-Reflection had warnings."
echo

info "== Step 4: Autonomous Knowledge Extraction & Selective Web Research =="
"$VENV_PYTHON" "$SCRIPT_DIR/extract_knowledge.py" || warn "Knowledge extraction had warnings."
echo

info "== Step 5: Second Brain Quality Linting =="
"$VENV_PYTHON" "$SCRIPT_DIR/wiki_lint.py" --no-llm || warn "Wiki Lint found warnings."
echo

success "Daily Learning & Reflection Complete! Second Brain is compounded."
