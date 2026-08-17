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
SKILLS_SCRIPT="$SCRIPT_DIR/sync-skills.sh"
REFLECTION_SCRIPT="$SCRIPT_DIR/cron-daily-reflection.sh"
LOG_FILE="$HOME/.hermes/sync-secondbrain.log"

if [ ! -f "$SYNC_SCRIPT" ]; then
    echo -e "${RED}[ERROR]${NC} Sync script not found at: $SYNC_SCRIPT"
    exit 1
fi

CRON_JOB_SECONDBRAIN="0 */12 * * * bash \"$SYNC_SCRIPT\" >> \"$LOG_FILE\" 2>&1"
CRON_JOB_SKILLS="0 0 * * * bash \"$SKILLS_SCRIPT\" >> \"$LOG_FILE\" 2>&1"
CRON_JOB_REFLECTION="5 0 * * * bash \"$REFLECTION_SCRIPT\" >> \"$LOG_FILE\" 2>&1"

# Remove existing cron jobs if they exist (so we can safely update them)
CURRENT_CRON="$(crontab -l 2>/dev/null || true)"
if echo "$CURRENT_CRON" | grep -q -e "sync-second-brain.sh" -e "sync-skills.sh" -e "cron-daily-reflection.sh"; then
    echo "$CURRENT_CRON" | grep -v -e "sync-second-brain.sh" -e "sync-skills.sh" -e "cron-daily-reflection.sh" | crontab -
    echo -e "${YELLOW}[INFO]${NC} Existing cron jobs found. Updating them..."
fi

# Append the new cron jobs to existing crontab
CLEAN_CRON="$(crontab -l 2>/dev/null || true)"
(echo "$CLEAN_CRON"; echo "$CRON_JOB_SECONDBRAIN"; echo "$CRON_JOB_SKILLS"; echo "$CRON_JOB_REFLECTION") | grep -v '^$' | crontab -
echo -e "${GREEN}[OK]${NC} Second Brain Auto-Backup scheduled every 12 hours!"
echo -e "${GREEN}[OK]${NC} Skills Auto-Backup scheduled every 24 hours (midnight)!"
echo -e "${GREEN}[OK]${NC} Daily Reflection & Journaling scheduled daily at 00:05!"
echo -e "       Log file will be written to: $LOG_FILE"
