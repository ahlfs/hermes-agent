#!/bin/bash
# ===================================================================
# Route Provider — Kelola routing provider melalui AG Proxy Bypass
# ===================================================================
# Script ini mendeteksi semua provider di config.yaml Hermes dan
# memungkinkan Anda memilih provider mana yang ingin dilewatkan
# melalui AG Proxy (port 8900) untuk bypass identitas Hermes.
#
# Bisa dijalankan sendiri atau otomatis dipanggil oleh setup-bypass.sh.
# ===================================================================

set -e

HERMES_DIR="$HOME/.hermes"
CONFIG_FILE="$HERMES_DIR/config.yaml"
PROXY_HOST="127.0.0.1"
PROXY_PORT="8900"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ File config tidak ditemukan: $CONFIG_FILE"
    exit 1
fi

# Gunakan Python untuk parsing YAML dan interaksi user
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_PYTHON="$SCRIPT_DIR/venv/bin/python3"
if [ ! -x "$HERMES_PYTHON" ]; then
    HERMES_PYTHON="$(which python3 2>/dev/null || true)"
fi

if [ ! -x "$HERMES_PYTHON" ]; then
    echo "❌ Python3 tidak ditemukan!"
    exit 1
fi

"$HERMES_PYTHON" << 'PYEOF'
import os
import sys
import re

config_path = os.path.expanduser("~/.hermes/config.yaml")
proxy_host = "127.0.0.1"
proxy_port = "8900"
proxy_marker = f"{proxy_host}:{proxy_port}"

# ── Simple YAML parser (no dependency needed) ────────────────────────
# Parse providers section from config.yaml without requiring PyYAML
def parse_providers(filepath):
    """Parse provider names and their base_url from config.yaml."""
    providers = {}
    current_provider = None
    in_providers = False

    with open(filepath, "r") as f:
        for line in f:
            stripped = line.rstrip()

            # Detect start of providers: block
            if re.match(r'^providers:\s*$', stripped):
                in_providers = True
                continue

            if in_providers:
                # Top-level key (not indented or single indent) = end of providers
                if stripped and not stripped.startswith(" "):
                    in_providers = False
                    continue

                # Provider name (2-space indent)
                match = re.match(r'^  (\S+):\s*$', stripped)
                if match:
                    current_provider = match.group(1)
                    providers[current_provider] = {"base_url": None, "_original_base_url": None}
                    continue

                # Provider property (4-space indent)
                if current_provider:
                    url_match = re.match(r'^    base_url:\s*(.+)$', stripped)
                    if url_match:
                        providers[current_provider]["base_url"] = url_match.group(1).strip()
                    orig_match = re.match(r'^    _original_base_url:\s*(.+)$', stripped)
                    if orig_match:
                        providers[current_provider]["_original_base_url"] = orig_match.group(1).strip()

    return providers


def update_provider_url(filepath, provider_name, new_url, original_url=None):
    """Update a provider's base_url in config.yaml, optionally saving original."""
    lines = []
    with open(filepath, "r") as f:
        lines = f.readlines()

    current_provider = None
    in_providers = False
    has_original = False
    result = []

    for line in lines:
        stripped = line.rstrip()

        if re.match(r'^providers:\s*$', stripped):
            in_providers = True
            result.append(line)
            continue

        if in_providers and stripped and not stripped.startswith(" "):
            in_providers = False

        if in_providers:
            match = re.match(r'^  (\S+):\s*$', stripped)
            if match:
                current_provider = match.group(1)

            if current_provider == provider_name:
                # Update base_url
                if re.match(r'^    base_url:', stripped):
                    result.append(f"    base_url: {new_url}\n")
                    # Add _original_base_url right after base_url if needed
                    if original_url:
                        result.append(f"    _original_base_url: {original_url}\n")
                    continue
                # Skip existing _original_base_url (we re-add it above)
                if re.match(r'^    _original_base_url:', stripped):
                    has_original = True
                    continue

        result.append(line)

    with open(filepath, "w") as f:
        f.writelines(result)


# ── Main ─────────────────────────────────────────────────────────────
print()
print("===================================================================")
print("🔀 ROUTE PROVIDER — Kelola Bypass AG Proxy")
print("===================================================================")
print()

providers = parse_providers(config_path)

if not providers:
    print("❌ Tidak ada provider ditemukan di config.yaml")
    sys.exit(0)

# Display providers
provider_list = []
print("  Provider yang ditemukan:\n")
for name, info in providers.items():
    base_url = info.get("base_url") or "N/A"
    original_url = info.get("_original_base_url")
    is_proxied = proxy_marker in str(base_url)

    if is_proxied and original_url:
        status = f"✅ Bypass → {original_url}"
    elif is_proxied:
        status = "✅ Bypass (default upstream)"
    else:
        status = "❌ Langsung (tanpa bypass)"

    idx = len(provider_list) + 1
    print(f"  {idx}. {name:20s}  {status}")
    print(f"     URL: {base_url}")
    if original_url and is_proxied:
        print(f"     Asli: {original_url}")
    print()
    provider_list.append((name, base_url, is_proxied, original_url))

print("===================================================================")
print("  Pilih provider yang ingin diubah:")
print("  - Masukkan NOMOR untuk toggle bypass (pisah koma untuk banyak)")
print("  - Ketik 'q' atau tekan Enter untuk keluar")
print("===================================================================")
choice = input("\n  Pilihan Anda: ").strip()

if not choice or choice.lower() == "q":
    print("\n  👋 Tidak ada perubahan.\n")
    sys.exit(0)

indices = []
for part in choice.split(","):
    part = part.strip()
    if part.isdigit():
        indices.append(int(part) - 1)

changed = False
for idx in indices:
    if idx < 0 or idx >= len(provider_list):
        print(f"  ⚠️  Nomor {idx+1} tidak valid, dilewati.")
        continue

    name, current_url, is_proxied, original_url = provider_list[idx]

    if is_proxied:
        # Toggle OFF: kembalikan ke URL asli
        restore_url = original_url or current_url
        if original_url:
            update_provider_url(config_path, name, original_url)
            print(f"  🔄 {name} → dikembalikan ke: {original_url}")
            changed = True
        else:
            print(f"  ℹ️  {name} sudah melewati proxy (tidak ada URL asli untuk dikembalikan).")
    else:
        # Toggle ON: arahkan ke proxy
        # Encode original URL into path-based routing
        # http://host:port/v1 → http://127.0.0.1:8900/proxy/host:port/v1
        if current_url and current_url != "N/A":
            # Extract host:port from URL
            url_clean = current_url.replace("http://", "").replace("https://", "")
            proxy_url = f"http://{proxy_marker}/proxy/{url_clean}"
            update_provider_url(config_path, name, proxy_url, current_url)
            print(f"  ✅ {name} → sekarang melewati AG Proxy!")
            print(f"     Rute: Hermes → Proxy:{proxy_port} → {current_url}")
            changed = True
        else:
            print(f"  ⚠️  {name} tidak memiliki base_url, dilewati.")

if changed:
    print(f"\n  ✅ Config disimpan!")
    print(f"  💡 Jalankan 'pkill -f hermes' untuk me-restart daemon.\n")
else:
    print(f"\n  👋 Tidak ada perubahan.\n")
PYEOF
