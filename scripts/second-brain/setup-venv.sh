#!/usr/bin/env bash
# Setup the isolated Python venv for Second Brain scripts.
# Run once after cloning hermes-agent:
#   bash scripts/second-brain/setup-venv.sh
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

VENV_DIR="$HOME/.hermes/venv-second-brain"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQ_FILE="$SCRIPT_DIR/requirements-second-brain.txt"

# ── Pre-flight checks ───────────────────────────────────────────────────
info "Checking prerequisites..."

# Check: git installed
if ! command -v git >/dev/null 2>&1; then
  error "'git' not found. Please install it first:"
  echo "  Ubuntu/Debian: sudo apt install git"
  echo "  macOS:         brew install git"
  exit 1
fi

# Check: python3 or uv available
HAS_UV=false
HAS_PYTHON3=false
UV_CMD=""

if command -v uv >/dev/null 2>&1; then
  HAS_UV=true
  UV_CMD="uv"
elif [ -x "$HOME/.hermes/bin/uv" ]; then
  HAS_UV=true
  UV_CMD="$HOME/.hermes/bin/uv"
elif [ -x "$HOME/.cargo/bin/uv" ]; then
  HAS_UV=true
  UV_CMD="$HOME/.cargo/bin/uv"
fi

if command -v python3 >/dev/null 2>&1; then
  HAS_PYTHON3=true
fi

if [ "$HAS_UV" = false ] && [ "$HAS_PYTHON3" = false ]; then
  error "Neither 'python3' nor 'uv' was found. At least one must be installed."
  echo "  Ubuntu/Debian: sudo apt install python3 python3-venv"
  echo "  macOS:         brew install python3"
  exit 1
fi

# Check: requirements file exists
if [ ! -f "$REQ_FILE" ]; then
  error "Requirements file not found: $REQ_FILE"
  error "Make sure you are running this script from the hermes-agent directory."
  exit 1
fi

success "All prerequisites met."
echo

# ── Create venv ──────────────────────────────────────────────────────────
info "Creating virtual environment at $VENV_DIR..."

if [ "$HAS_UV" = true ]; then
  info "Using 'uv' (faster)..."
  "$UV_CMD" venv "$VENV_DIR"
  "$UV_CMD" pip install -r "$REQ_FILE" --python "$VENV_DIR"
else
  info "Using 'python3 -m venv'..."
  if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
    error "Failed to create venv using python3. You are likely missing the python3-venv package."
    error "Try running: sudo apt install python3-venv (or python3.x-venv for your version)"
    rm -rf "$VENV_DIR"
    exit 1
  fi
  
  if [ ! -x "$VENV_DIR/bin/pip" ]; then
    error "pip is not available inside the venv. Try installing python3-venv:"
    echo "  Ubuntu/Debian: sudo apt install python3-venv"
    rm -rf "$VENV_DIR"
    exit 1
  fi
  "$VENV_DIR/bin/pip" install --upgrade pip -q
  "$VENV_DIR/bin/pip" install -r "$REQ_FILE"
fi

echo
success "Venv successfully created at: $VENV_DIR"
info "Test with: $VENV_DIR/bin/python -c 'import faster_whisper; print(\"OK\")'"
