#!/usr/bin/env bash

MEMORY_FILE="$HOME/.hermes/memories/MEMORY.md"

if [ ! -f "$MEMORY_FILE" ]; then
    echo "Error: $MEMORY_FILE not found."
    exit 1
fi

echo "Gathering system environment info..."

# OS Info
OS_INFO=$(uname -a)
if [ -f "/etc/os-release" ]; then
    PRETTY_NAME=$(grep ^PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_INFO="$PRETTY_NAME ($(uname -m))"
fi

# Tool checks
check_tool() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "✅ $1 is installed"
    else
        echo "❌ $1 is NOT installed"
    fi
}

TOOLS_STATUS=""
for tool in docker php composer node npm pnpm python3; do
    TOOLS_STATUS+="- $(check_tool $tool)\n"
done

# Sudo check
SUDO_STATUS=""
if sudo -n true 2>/dev/null; then
    SUDO_STATUS="✅ User has passwordless sudo."
else
    SUDO_STATUS="❌ User does NOT have passwordless sudo (requires password)."
fi

# Construct the environment block
ENV_BLOCK="Workspace environment ($HOME/workspace, $OS_INFO):
$TOOLS_STATUS
$SUDO_STATUS
*(Note for agent: Do not assume tools are available if marked with ❌. If sudo requires password, do not run sudo commands directly — ask user to run them or confirm before attempting.)*"

# Escape newlines for sed or use awk to replace between markers
awk -v env_block="$ENV_BLOCK" '
  BEGIN { in_block = 0 }
  /<!-- ENVIRONMENT_START -->/ {
    print
    print env_block
    in_block = 1
    next
  }
  /<!-- ENVIRONMENT_END -->/ {
    in_block = 0
    print
    next
  }
  !in_block { print }
' "$MEMORY_FILE" > "${MEMORY_FILE}.tmp" && mv "${MEMORY_FILE}.tmp" "$MEMORY_FILE"

echo "Memory updated successfully!"
