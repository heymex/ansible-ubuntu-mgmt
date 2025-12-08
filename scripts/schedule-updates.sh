#!/bin/bash
#
# Example script for scheduling Ansible system updates via cron
#
# This script can be called from cron to run system updates.
# It includes logging and error handling.
#
# Usage in crontab:
#   0 2 * * * /path/to/ansible-ubuntu-mgmt/scripts/schedule-updates.sh
#
# Or for production only:
#   0 3 * * 0 /path/to/ansible-ubuntu-mgmt/scripts/schedule-updates.sh production

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
LOG_FILE="$LOG_DIR/ansible-updates-$(date +%Y%m%d-%H%M%S).log"
LIMIT="${1:-}"  # Optional limit (e.g., "production", "staging")

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Change to project directory
cd "$PROJECT_DIR"

log "Starting scheduled system updates"
log "Project directory: $PROJECT_DIR"
log "Log file: $LOG_FILE"

# Build ansible-playbook command
PLAYBOOK_CMD="ansible-playbook playbooks/system-updates.yml"

if [ -n "$LIMIT" ]; then
    PLAYBOOK_CMD="$PLAYBOOK_CMD --limit $LIMIT"
    log "Limiting to group: $LIMIT"
fi

# Run the playbook
if $PLAYBOOK_CMD >> "$LOG_FILE" 2>&1; then
    log "System updates completed successfully"
    exit 0
else
    log "ERROR: System updates failed. Check log file: $LOG_FILE"
    exit 1
fi
