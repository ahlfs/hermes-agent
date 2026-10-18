#!/usr/bin/env bash
# ============================================================================
# Hermes Agent — Second Brain Edition (All-In-One Unified Setup Wizard)
# ============================================================================
# Usage:
#   ./setup-secondbrain.sh
#
# This script:
# 1. Cleans any stale update/install lock files
# 2. Verifies system tools (ffmpeg, tesseract, git, curl, build tools)
# 3. Ensures Node.js runtime is installed (auto-installs standalone Node if needed)
# 4. Runs core Hermes Agent setup (uv, Python 3.11, venv, locked deps, cli launcher)
# 5. Provisions Browser Use CLI tools
# 6. Sets up the isolated Second Brain environment (faster-whisper, pypdf, ocr)
# 7. Injects memory templates (MEMORY.md, USER.md, SOUL.md) and auto-detects OS
# 8. Prepares the Obsidian Vault structure and .env configuration
# 9. Schedules Second Brain cron jobs
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

mkdir -p "$HOME/.hermes" "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

echo ""
echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     🧠 Hermes Agent — Second Brain Edition Setup Wizard         ║${NC}"
echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Clean Stale Locks ──────────────────────────────────────────────
echo -e "${CYAN}[1/7]${NC} Memeriksa status sistem & membersihkan stale lock..."
for lock in "$HOME/.hermes/.hermes-update-in-progress.lock" "$HOME/.hermes/.hermes-update-in-progress"; do
    if [ -f "$lock" ]; then
        if ! pgrep -f "source_completion|hermes update" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠${NC} Membersihkan lock file lama: $lock"
            rm -f "$lock"
        fi
    fi
done
echo -e "${GREEN}✓${NC} Sistem bersih dari lock lama"

# ── Step 2: System Packages Check ──────────────────────────────────────────
echo ""
echo -e "${CYAN}[2/7]${NC} Memeriksa dependensi sistem dasar..."
MISSING_PKGS=()
command -v ffmpeg >/dev/null 2>&1 || MISSING_PKGS+=("ffmpeg")
command -v tesseract >/dev/null 2>&1 || MISSING_PKGS+=("tesseract")
command -v git >/dev/null 2>&1 || MISSING_PKGS+=("git")
command -v curl >/dev/null 2>&1 || MISSING_PKGS+=("curl")

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Paket berikut belum terpasang di sistem: ${MISSING_PKGS[*]}"
    if command -v sudo >/dev/null 2>&1; then
        REPLY="y"
        if [ -c /dev/tty ] && (: </dev/tty) 2>/dev/null; then
            read -p "Pasang paket yang kurang (${MISSING_PKGS[*]}) otomatis via sudo? [Y/n] " -n 1 -r REPLY < /dev/tty
            echo ""
        fi
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y ffmpeg tesseract-ocr build-essential git curl || true
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y ffmpeg tesseract git curl gcc-c++ || true
            elif command -v pacman >/dev/null 2>&1; then
                sudo pacman -S --noconfirm ffmpeg tesseract git curl base-devel || true
            fi
        fi
    else
        echo -e "${YELLOW}ℹ${NC} Anda tidak memiliki sudo. Audio transcription atau OCR mungkin memerlukan pemasangan manual:"
        echo "   sudo apt install -y ${MISSING_PKGS[*]}"
    fi
else
    echo -e "${GREEN}✓${NC} Semua dependensi sistem (ffmpeg, tesseract, git, curl) lengkap"
fi

# ── Step 3: Node.js Runtime Check & Standalone Provisioning ────────────────
echo ""
echo -e "${CYAN}[3/7]${NC} Memeriksa runtime Node.js..."
HAS_VALID_NODE=false
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node --version | cut -d'.' -f1 | tr -d 'v')
    if [ "$NODE_MAJOR" -ge 18 ]; then
        HAS_VALID_NODE=true
        echo -e "${GREEN}✓${NC} Node.js $(node --version) sudah terpasang"
    fi
fi

if [ "$HAS_VALID_NODE" = false ]; then
    echo -e "${CYAN}→${NC} Node.js belum ada (atau < v18). Mengunduh Node.js LTS mandiri ke ~/.hermes/node/..."
    NODE_VER="22.14.0"
    ARCH=$(uname -m)
    NODE_ARCH="x64"
    [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ] && NODE_ARCH="arm64"
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    DEST="$HOME/.hermes/node"
    mkdir -p "$DEST"

    TARBALL_XZ="node-v${NODE_VER}-${OS}-${NODE_ARCH}.tar.xz"
    URL_XZ="https://nodejs.org/dist/v${NODE_VER}/${TARBALL_XZ}"
    TARBALL_GZ="node-v${NODE_VER}-${OS}-${NODE_ARCH}.tar.gz"
    URL_GZ="https://nodejs.org/dist/v${NODE_VER}/${TARBALL_GZ}"

    DOWNLOAD_OK=false
    if command -v xz >/dev/null 2>&1; then
        if curl -fsSL "$URL_XZ" | tar -xJ -C "$DEST" --strip-components=1 2>/dev/null; then
            DOWNLOAD_OK=true
        fi
    fi

    if [ "$DOWNLOAD_OK" = false ]; then
        if curl -fsSL "$URL_GZ" | tar -xz -C "$DEST" --strip-components=1 2>/dev/null; then
            DOWNLOAD_OK=true
        fi
    fi

    if [ "$DOWNLOAD_OK" = true ] && [ -x "$DEST/bin/node" ]; then
        ln -sf "$DEST/bin/node" "$HOME/.local/bin/node"
        ln -sf "$DEST/bin/npm" "$HOME/.local/bin/npm"
        ln -sf "$DEST/bin/npx" "$HOME/.local/bin/npx"
        echo -e "${GREEN}✓${NC} Node.js $("$DEST/bin/node" --version) berhasil dipasang tanpa perlu root"
    else
        echo -e "${YELLOW}⚠${NC} Unduhan Node.js mandiri gagal. Anda dapat memasangnya nanti via nvm / paket sistem."
    fi
fi

# ── Step 4: Core Hermes Engine Setup ───────────────────────────────────────
echo ""
echo -e "${CYAN}[4/7]${NC} Memasang Core Engine Hermes (uv, Python 3.11, venv, dependencies)..."
if [ -f "./setup-hermes.sh" ]; then
    HERMES_SKIP_SETUP=1 bash ./setup-hermes.sh --skip-setup
else
    echo -e "${RED}✗${NC} setup-hermes.sh tidak ditemukan!"
    exit 1
fi

# ── Step 5: Browser Automation Tools ───────────────────────────────────────
echo ""
echo -e "${CYAN}[5/7]${NC} Menyiapkan Browser Use CLI (web tools)..."
UV_BIN="$(command -v uv 2>/dev/null || echo "$HOME/.local/bin/uv")"
if [ -x "$UV_BIN" ]; then
    if ! command -v browser-use >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/browser-use" ]; then
        echo -e "${CYAN}→${NC} Mengunduh browser-use CLI..."
        "$UV_BIN" tool install browser-use >/dev/null 2>&1 || true
        if command -v browser-use >/dev/null 2>&1 || [ -x "$HOME/.local/bin/browser-use" ]; then
            echo -e "${GREEN}✓${NC} Browser Use CLI siap"
        else
            echo -e "${YELLOW}ℹ${NC} Browser Use CLI dilewati (dapat dipasang nanti via 'hermes tools')"
        fi
    else
        echo -e "${GREEN}✓${NC} Browser Use CLI sudah terpasang"
    fi
fi

# ── Step 6: Second Brain Environment Setup ────────────────────────────────
echo ""
echo -e "${CYAN}[6/7]${NC} Menginisialisasi Environment, Vault, & Memori Second Brain..."
if [ -f "scripts/second-brain/setup-venv.sh" ]; then
    bash scripts/second-brain/setup-venv.sh
else
    echo -e "${RED}✗${NC} scripts/second-brain/setup-venv.sh tidak ditemukan!"
    exit 1
fi

# ── Step 7: Install Cron Jobs (Optional) ───────────────────────────────────
echo ""
echo -e "${CYAN}[7/7]${NC} Menyiapkan Tugas Terjadwal (Cron Jobs Second Brain)..."
REPLY="y"
if [ -c /dev/tty ] && (: </dev/tty) 2>/dev/null; then
    read -p "Aktifkan otomatisasi cron (sync tiap 12 jam, refleksi harian tiap tengah malam)? [Y/n] " -n 1 -r REPLY < /dev/tty
    echo ""
fi
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    if [ -f "scripts/second-brain/install-cron.sh" ]; then
        bash scripts/second-brain/install-cron.sh
    fi
else
    echo -e "${YELLOW}ℹ${NC} Cron jobs dilewati. Anda bisa memasangnya nanti via: bash scripts/second-brain/install-cron.sh"
fi

# ── Final Verification & Finished ──────────────────────────────────────────
echo ""
echo -e "${CYAN}→${NC} Verifikasi akhir..."
if command -v hermes >/dev/null 2>&1 || [ -x "$HOME/.local/bin/hermes" ]; then
    HERMES_VERSION=$("$HOME/.local/bin/hermes" --version 2>/dev/null || echo "Hermes CLI")
    echo -e "${GREEN}✓${NC} $HERMES_VERSION siap digunakan!"
fi

echo ""
echo -e "${GREEN}═════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✨ Setup Hermes Second Brain Edition Sukses & Lengkap!${NC}"
echo -e "${GREEN}═════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Perintah cepat:"
echo "  • Mulai chat interaktif : hermes"
echo "  • Cek konfigurasi model : hermes model"
echo "  • Manual sync vault     : bash scripts/second-brain/sync-second-brain.sh"
echo "  • Cek status cron       : hermes cron list"
echo ""
echo -e "Catatan: Jika command 'hermes' belum terbaca di terminal ini, jalankan:"
echo -e "  ${CYAN}source ~/.bashrc${NC}  (atau buka tab terminal baru)"
echo ""
