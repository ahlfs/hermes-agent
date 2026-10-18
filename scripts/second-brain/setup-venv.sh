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
if [ "$(id -u)" -eq 0 ]; then
  warn "You are executing this setup script as ROOT."
  warn "It is highly recommended to run Hermes Agent and Second Brain under a dedicated non-root user with sudo privileges."
  read -r -p "Do you want to continue running as root anyway? (y/N): " confirm || confirm="N"
  if [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
    error "Setup cancelled. Please re-run under a regular user."
    exit 1
  fi
fi

info "Checking prerequisites..."

# Check and clean up stale update locks if previous install was interrupted
for lock_candidate in "$HOME/.hermes/.hermes-update-in-progress.lock" "$HOME/.hermes/.hermes-update-in-progress"; do
  if [ -f "$lock_candidate" ]; then
    if ! pgrep -f "source_completion|hermes update" >/dev/null 2>&1; then
      warn "Found stale update lock ($lock_candidate) without active process. Removing it..."
      rm -f "$lock_candidate"
    fi
  fi
done

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
elif [ -x "$HOME/.local/bin/uv" ]; then
  HAS_UV=true
  UV_CMD="$HOME/.local/bin/uv"
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

echo "[OK] Dependencies installed successfully."

echo
echo "[INFO] Initializing Second Brain templates..."
TEMPLATES_DIR="$SCRIPT_DIR/templates"
HERMES_MEMORIES_DIR="$HOME/.hermes/memories"

if [ -d "$TEMPLATES_DIR" ]; then
  mkdir -p "$HERMES_MEMORIES_DIR"

  if [ -f "$HERMES_MEMORIES_DIR/MEMORY.md" ]; then
    echo "[INFO] Backing up existing MEMORY.md..."
    mv "$HERMES_MEMORIES_DIR/MEMORY.md" "$HERMES_MEMORIES_DIR/MEMORY.md.backup"
  fi
  echo "[INFO] Overwriting $HERMES_MEMORIES_DIR/MEMORY.md with template..."
  cp "$TEMPLATES_DIR/MEMORY.md" "$HERMES_MEMORIES_DIR/MEMORY.md"

  if [ -f "$HERMES_MEMORIES_DIR/USER.md" ]; then
    echo "[INFO] Backing up existing USER.md..."
    mv "$HERMES_MEMORIES_DIR/USER.md" "$HERMES_MEMORIES_DIR/USER.md.backup"
  fi
  echo "[INFO] Overwriting $HERMES_MEMORIES_DIR/USER.md with template..."
  cp "$TEMPLATES_DIR/USER.md" "$HERMES_MEMORIES_DIR/USER.md"

  HERMES_ROOT_DIR="$HOME/.hermes"
  if [ -f "$TEMPLATES_DIR/SOUL.md" ]; then
    if [ -f "$HERMES_ROOT_DIR/SOUL.md" ]; then
      echo "[INFO] Backing up existing SOUL.md..."
      mv "$HERMES_ROOT_DIR/SOUL.md" "$HERMES_ROOT_DIR/SOUL.md.backup"
    fi
    echo "[INFO] Overwriting $HERMES_ROOT_DIR/SOUL.md with template..."
    cp "$TEMPLATES_DIR/SOUL.md" "$HERMES_ROOT_DIR/SOUL.md"
  fi

  # Inject dynamic OS environment into the fresh MEMORY.md
  if [ -f "$SCRIPT_DIR/../init-env-memory.sh" ]; then
    chmod +x "$SCRIPT_DIR/../init-env-memory.sh"
    echo "[INFO] Initializing dynamic OS environment in MEMORY.md..."
    "$SCRIPT_DIR/../init-env-memory.sh" > /dev/null
  fi
fi

# ── Auto-configure Vault & Directory Structure ───────────────────────────
HERMES_ENV="$HOME/.hermes/.env"
DEFAULT_VAULT="$HOME/obsidian/memo"
mkdir -p "$HOME/.hermes"

if [ -f "$HERMES_ENV" ]; then
  if ! grep -q "OBSIDIAN_VAULT_DIR" "$HERMES_ENV"; then
    echo "" >> "$HERMES_ENV"
    echo "# Second Brain Vault Directory" >> "$HERMES_ENV"
    echo "OBSIDIAN_VAULT_DIR=$DEFAULT_VAULT" >> "$HERMES_ENV"
    info "Configured OBSIDIAN_VAULT_DIR in $HERMES_ENV"
  fi
else
  cat > "$HERMES_ENV" <<EOF
# Second Brain Vault Directory
OBSIDIAN_VAULT_DIR=$DEFAULT_VAULT
EOF
  chmod 600 "$HERMES_ENV"
  info "Created $HERMES_ENV with default OBSIDIAN_VAULT_DIR"
fi

TARGET_VAULT_DIR="$(grep "^OBSIDIAN_VAULT_DIR=" "$HERMES_ENV" 2>/dev/null | head -n 1 | cut -d'=' -f2- | tr -d '"\x27' || true)"
[ -z "$TARGET_VAULT_DIR" ] && TARGET_VAULT_DIR="$DEFAULT_VAULT"

info "Initializing Second Brain folder structure in $TARGET_VAULT_DIR..."
mkdir -p "$TARGET_VAULT_DIR/01-Audio"
mkdir -p "$TARGET_VAULT_DIR/02-Documents"
mkdir -p "$TARGET_VAULT_DIR/03-Notes/Transcripts"
mkdir -p "$TARGET_VAULT_DIR/03-Notes/Extracted-Docs"
mkdir -p "$TARGET_VAULT_DIR/04-Wiki"
mkdir -p "$TARGET_VAULT_DIR/05-Projects"
mkdir -p "$TARGET_VAULT_DIR/06-Tasks"
mkdir -p "$TARGET_VAULT_DIR/07-Daily"

if [ ! -f "$TARGET_VAULT_DIR/WIKI_SCHEMA.md" ] && [ -f "$TEMPLATES_DIR/WIKI_SCHEMA.md" ]; then
  cp "$TEMPLATES_DIR/WIKI_SCHEMA.md" "$TARGET_VAULT_DIR/WIKI_SCHEMA.md"
  info "Copied WIKI_SCHEMA.md to $TARGET_VAULT_DIR"
fi

echo
echo "[OK] Second Brain environment setup is complete!"
success "Venv successfully created at: $VENV_DIR"
info "Test with: $VENV_DIR/bin/python -c 'import faster_whisper; print(\"OK\")'"
