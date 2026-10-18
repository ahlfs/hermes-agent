#!/usr/bin/env bash
# ============================================================================
# Hermes Agent — Second Brain Edition (All-In-One Unified Setup)
# ============================================================================
# Usage:
#   ./setup-secondbrain.sh
#
# This script:
# 1. Cleans any stale update/install lock files
# 2. Ensures system prerequisites (git, curl, python, uv)
# 3. Runs core Hermes Agent setup (venv, locked dependencies, cli launcher)
# 4. Sets up the isolated Second Brain environment (faster-whisper, pypdf, ocr)
# 5. Injects memory templates (MEMORY.md, USER.md, SOUL.md) and auto-detects OS
# 6. Prepares the Obsidian Vault structure and .env configuration
# 7. Optionally schedules Second Brain cron jobs
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     🧠 Hermes Agent — Second Brain Edition Setup Wizard         ║${NC}"
echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 0: Clean Stale Locks ──────────────────────────────────────────────
echo -e "${CYAN}[1/5]${NC} Memeriksa status sistem & membersihkan stale lock..."
for lock in "$HOME/.hermes/.hermes-update-in-progress.lock" "$HOME/.hermes/.hermes-update-in-progress"; do
    if [ -f "$lock" ]; then
        if ! pgrep -f "source_completion|hermes update" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠${NC} Membersihkan lock file lama: $lock"
            rm -f "$lock"
        fi
    fi
done

# ── Step 1: Core Hermes Setup ─────────────────────────────────────────────
echo ""
echo -e "${CYAN}[2/5]${NC} Memasang Core Engine Hermes..."
if [ -f "./setup-hermes.sh" ]; then
    bash ./setup-hermes.sh
else
    echo -e "${RED}✗${NC} setup-hermes.sh tidak ditemukan!"
    exit 1
fi

# Ensure ~/.local/bin is available for current session
export PATH="$HOME/.local/bin:$PATH"

# ── Step 2: Second Brain Environment Setup ────────────────────────────────
echo ""
echo -e "${CYAN}[3/5]${NC} Menginisialisasi Environment & Tools Second Brain..."
if [ -f "scripts/second-brain/setup-venv.sh" ]; then
    bash scripts/second-brain/setup-venv.sh
else
    echo -e "${RED}✗${NC} scripts/second-brain/setup-venv.sh tidak ditemukan!"
    exit 1
fi

# ── Step 3: Install Cron Jobs (Optional) ───────────────────────────────────
echo ""
echo -e "${CYAN}[4/5]${NC} Menyiapkan Tugas Terjadwal (Cron Jobs Second Brain)..."
read -p "Aktifkan otomatisasi cron (sync tiap 12 jam, refleksi harian tiap tengah malam)? [Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    if [ -f "scripts/second-brain/install-cron.sh" ]; then
        bash scripts/second-brain/install-cron.sh
    fi
else
    echo -e "${YELLOW}ℹ${NC} Cron jobs dilewati. Anda bisa memasangnya nanti via: bash scripts/second-brain/install-cron.sh"
fi

# ── Step 4: Verification & Finished ────────────────────────────────────────
echo ""
echo -e "${CYAN}[5/5]${NC} Verifikasi akhir..."
if command -v hermes >/dev/null 2>&1; then
    HERMES_VERSION=$(hermes --version 2>/dev/null || echo "Hermes CLI")
    echo -e "${GREEN}✓${NC} $HERMES_VERSION siap digunakan!"
else
    echo -e "${YELLOW}⚠${NC} Command hermes belum terbaca di PATH sesi aktif."
    echo -e "   Jalankan: ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC} atau ${CYAN}source ~/.bashrc${NC}"
fi

echo ""
echo -e "${GREEN}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✨ Setup Hermes Second Brain Edition Sukses!${NC}"
echo -e "${GREEN}═════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Perintah cepat:"
echo "  • Mulai chat interaktif : hermes"
echo "  • Cek konfigurasi model : hermes model"
echo "  • Manual sync vault     : bash scripts/second-brain/sync-second-brain.sh"
echo "  • Cek status cron       : hermes cron list"
echo ""
