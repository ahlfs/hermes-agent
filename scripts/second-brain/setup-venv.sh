#!/usr/bin/env bash
# Setup the isolated Python venv for Second Brain scripts.
# Run once after cloning hermes-agent:
#   bash scripts/second-brain/setup-venv.sh
set -euo pipefail

VENV_DIR="$HOME/.hermes/venv-second-brain"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQ_FILE="$SCRIPT_DIR/requirements-second-brain.txt"

echo "Creating venv at $VENV_DIR..."

if command -v uv >/dev/null 2>&1; then
  uv venv "$VENV_DIR"
  uv pip install -r "$REQ_FILE" --python "$VENV_DIR"
else
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --upgrade pip -q
  "$VENV_DIR/bin/pip" install -r "$REQ_FILE"
fi

echo
echo "Done! Venv created at: $VENV_DIR"
echo "Test with: $VENV_DIR/bin/python -c 'import faster_whisper; print(\"OK\")'"
