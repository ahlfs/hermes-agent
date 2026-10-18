#!/usr/bin/env bash
# ============================================================================
# Hermes Agent — Second Brain Edition (One-Line Web Installer)
# ============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ahlfs/hermes-agent/main/install-secondbrain.sh | bash
# ============================================================================

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TARGET_DIR="$HOME/.hermes/hermes-agent"
REPO_URL="https://github.com/ahlfs/hermes-agent.git"

echo ""
echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     🧠 Hermes Agent — Second Brain Edition Quick Setup          ║${NC}"
echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
    echo -e "${YELLOW}→${NC} git tidak ditemukan. Mencoba memasang git..."
    if command -v brew >/dev/null 2>&1; then
        brew install git curl
    elif [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; then
        SUDO_CMD=""
        [ "$(id -u)" -ne 0 ] && SUDO_CMD="sudo"
        if command -v apt-get >/dev/null 2>&1; then
            $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y git curl
        elif command -v dnf >/dev/null 2>&1; then
            $SUDO_CMD dnf install -y git curl
        elif command -v pacman >/dev/null 2>&1; then
            $SUDO_CMD pacman -S --noconfirm git curl
        fi
    else
        echo -e "${RED}✗${NC} Silakan pasang 'git' dan 'curl' terlebih dahulu di sistem Anda."
        exit 1
    fi
fi

# Clone or update repo
mkdir -p "$HOME/.hermes"
if [ -d "$TARGET_DIR/.git" ]; then
    echo -e "${CYAN}→${NC} Folder repositori sudah ada di $TARGET_DIR. Memperbarui..."
    cd "$TARGET_DIR"
    git remote set-url origin "$REPO_URL" 2>/dev/null || true
    git fetch origin
    git checkout -B main origin/main
else
    echo -e "${CYAN}→${NC} Mengunduh Hermes Second Brain Edition ke $TARGET_DIR..."
    git clone "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

# Execute all-in-one setup wizard
chmod +x ./setup-secondbrain.sh ./setup-hermes.sh 2>/dev/null || true
exec ./setup-secondbrain.sh "$@"
