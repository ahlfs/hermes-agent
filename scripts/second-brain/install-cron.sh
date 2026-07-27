#!/usr/bin/env bash
# Install an hourly cron job for the Hermes Agent Second Brain Auto-Backup.

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}[INFO]${NC} Setting up Auto-Backup Cron Job..."

# Get absolute path to the sync script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-second-brain.sh"
LOG_FILE="$HOME/.hermes/sync-secondbrain.log"

if [ ! -f "$SYNC_SCRIPT" ]; then
    echo -e "${RED}[ERROR]${NC} Sync script not found at: $SYNC_SCRIPT"
    exit 1
fi

CRON_JOB="0 * * * * bash \"$SYNC_SCRIPT\" >> \"$LOG_FILE\" 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "sync-second-brain.sh"; then
    echo -e "${YELLOW}[WARN]${NC} Cron job already exists! Skipping installation."
else
    # Append the new cron job to existing crontab
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}[OK]${NC} Auto-Backup successfully scheduled every hour!"
    echo -e "       Log file will be written to: $LOG_FILE"
fi
