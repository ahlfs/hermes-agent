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

# ── Load environment variables ───────────────────────────────────────────
HERMES_ENV="$HOME/.hermes/.env"
if [ ! -f "$HERMES_ENV" ]; then
  error "File $HERMES_ENV tidak ditemukan."
  error "Pastikan Anda sudah mengkonfigurasi file .env terlebih dahulu (Langkah 4 di README)."
  exit 1
fi

info "Membaca konfigurasi dari $HERMES_ENV..."
export $(grep -v '^#' "$HERMES_ENV" | grep -v '^\s*$' | xargs)

# ── Validate required variables ──────────────────────────────────────────
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPO_CONFIG="${GITHUB_REPO_CONFIG:-hermes-config}"
GITHUB_REPO_SECONDBRAIN="${GITHUB_REPO_SECONDBRAIN:-second-brain}"

if [ -z "${OBSIDIAN_VAULT_DIR:-}" ]; then
  export OBSIDIAN_VAULT_DIR="${SECOND_BRAIN_VAULT:-$HOME/obsidian/memo}"
fi

if [ -z "$GITHUB_USERNAME" ]; then
  error "GITHUB_USERNAME belum diatur di $HERMES_ENV."
  error "Tambahkan baris berikut ke file .env Anda:"
  echo "  GITHUB_USERNAME=your_github_username"
  exit 1
fi

info "GitHub Username    : $GITHUB_USERNAME"
info "Config Repo        : $GITHUB_REPO_CONFIG"
info "Second Brain Repo  : $GITHUB_REPO_SECONDBRAIN"
info "Obsidian Vault Dir : $OBSIDIAN_VAULT_DIR"
echo

# ── Verify SSH access to GitHub ──────────────────────────────────────────
info "Memeriksa koneksi SSH ke GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  success "Koneksi SSH ke GitHub berhasil."
else
  warn "Tidak dapat memverifikasi koneksi SSH ke GitHub."
  warn "Pastikan kunci SSH Anda sudah ditambahkan ke akun GitHub."
  warn "Melanjutkan proses... (akan gagal jika SSH belum dikonfigurasi)"
fi
echo

# ── Restore Config (Agent Brain) ────────────────────────────────────────
REMOTE_CONFIG="git@github.com:${GITHUB_USERNAME}/${GITHUB_REPO_CONFIG}.git"
TEMP_CONFIG="$HOME/.hermes/_restore-config-tmp"

info "═══════════════════════════════════════════════════"
info "  TAHAP 1: Memulihkan Config (Agent Brain)"
info "═══════════════════════════════════════════════════"

# Check if the remote repo actually exists / is accessible
if git ls-remote "$REMOTE_CONFIG" &>/dev/null; then
  info "Mengunduh repositori config dari $REMOTE_CONFIG..."

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
        info "  Memulihkan direktori: $item/"
        cp -r "$src/." "$dest/" 2>/dev/null || cp -r "$src" "$dest"
      else
        info "  Memulihkan file: $item"
        cp "$src" "$dest"
      fi
    else
      warn "  $item tidak ditemukan di backup — dilewati."
    fi
  done

  # Clean up
  rm -rf "$TEMP_CONFIG"
  success "Config berhasil dipulihkan!"
else
  warn "Repositori $REMOTE_CONFIG tidak dapat diakses atau belum ada."
  warn "Melewati pemulihan Config."
fi
echo

# ── Restore Second Brain (Knowledge Base) ────────────────────────────────
REMOTE_SB="git@github.com:${GITHUB_USERNAME}/${GITHUB_REPO_SECONDBRAIN}.git"

info "═══════════════════════════════════════════════════"
info "  TAHAP 2: Memulihkan Second Brain (Knowledge Base)"
info "═══════════════════════════════════════════════════"

if git ls-remote "$REMOTE_SB" &>/dev/null; then
  if [ -d "$OBSIDIAN_VAULT_DIR/.git" ]; then
    # Vault already exists and is a git repo — just pull latest
    info "Vault sudah ada dan merupakan repo Git. Melakukan git pull..."
    cd "$OBSIDIAN_VAULT_DIR"
    git pull origin main && success "Second Brain berhasil diperbarui!" \
      || warn "Git pull gagal. Mungkin ada konflik yang perlu diselesaikan."
  elif [ -d "$OBSIDIAN_VAULT_DIR" ] && [ "$(ls -A "$OBSIDIAN_VAULT_DIR" 2>/dev/null)" ]; then
    # Directory exists and is not empty, but not a git repo
    warn "Direktori $OBSIDIAN_VAULT_DIR sudah ada dan tidak kosong, tapi bukan repo Git."
    warn "Untuk menghindari kehilangan data, pemulihan Second Brain dilewati."
    warn "Solusi: Kosongkan direktori tersebut atau hapus, lalu jalankan skrip ini lagi."
  else
    # Directory doesn't exist or is empty — clone directly
    info "Mengunduh Second Brain dari $REMOTE_SB..."
    mkdir -p "$(dirname "$OBSIDIAN_VAULT_DIR")"
    rm -rf "$OBSIDIAN_VAULT_DIR"  # remove empty dir if exists
    git clone "$REMOTE_SB" "$OBSIDIAN_VAULT_DIR"
    success "Second Brain berhasil dipulihkan ke $OBSIDIAN_VAULT_DIR!"
  fi
else
  warn "Repositori $REMOTE_SB tidak dapat diakses atau belum ada."
  warn "Melewati pemulihan Second Brain."
fi
echo

# ── Summary ──────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════"
success "Proses pemulihan selesai!"
echo "═══════════════════════════════════════════════════"
echo
info "Langkah selanjutnya:"
echo "  1. Muat ulang shell Anda:  source ~/.bashrc"
echo "  2. Mulai agen:             hermes"
echo "  3. Verifikasi memori agen bekerja dengan bertanya:"
echo "     \"Apa yang kamu ingat tentang saya?\""
echo
