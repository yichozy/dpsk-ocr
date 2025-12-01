#!/bin/bash

# auto_restart.sh - Auto-restart DeepSeek OCR PDF Service at midnight UTC+8
# Usage:
#   ./auto_restart.sh          - Run once at next midnight UTC+8
#   ./auto_restart.sh --daemon - Run as daemon, restart every midnight UTC+8
#   ./auto_restart.sh --cron   - Setup cron job for auto-restart
#   ./auto_restart.sh --stop   - Stop the daemon

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="/tmp/deepseek_ocr_auto_restart.pid"
LOG_FILE="/tmp/deepseek_ocr_auto_restart.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_seconds_until_midnight_utc8() {
    # Get current time in UTC+8
    local current_epoch=$(date +%s)

    # Calculate midnight UTC+8 (16:00 UTC previous day or today)
    # UTC+8 midnight = 16:00 UTC
    local current_utc_hour=$(date -u +%H)
    local current_utc_min=$(date -u +%M)
    local current_utc_sec=$(date -u +%S)

    # Seconds since midnight UTC
    local seconds_since_utc_midnight=$((current_utc_hour * 3600 + current_utc_min * 60 + current_utc_sec))

    # UTC+8 midnight is at 16:00 UTC (16 * 3600 = 57600 seconds)
    local target_utc_seconds=57600

    local seconds_until_target
    if [ $seconds_since_utc_midnight -lt $target_utc_seconds ]; then
        # Target is today
        seconds_until_target=$((target_utc_seconds - seconds_since_utc_midnight))
    else
        # Target is tomorrow
        seconds_until_target=$((86400 - seconds_since_utc_midnight + target_utc_seconds))
    fi

    echo $seconds_until_target
}

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

do_restart() {
    log "${CYAN}=== Auto-restart triggered ===${NC}"
    log "Current time (UTC): $(date -u '+%Y-%m-%d %H:%M:%S')"
    log "Current time (UTC+8): $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')"

    cd "$SCRIPT_DIR"

    if [ -f "./restart.sh" ]; then
        log "Executing restart.sh..."
        ./restart.sh >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log "${GREEN}Service restarted successfully${NC}"
        else
            log "${RED}Service restart failed${NC}"
        fi
    else
        log "${RED}Error: restart.sh not found in $SCRIPT_DIR${NC}"
        return 1
    fi
}

run_daemon() {
    log "${GREEN}=== Starting auto-restart daemon ===${NC}"
    log "Service will restart at midnight UTC+8 (16:00 UTC) daily"

    # Save daemon PID
    echo $$ > "$PID_FILE"

    while true; do
        local seconds_until=$(get_seconds_until_midnight_utc8)
        local formatted=$(format_duration $seconds_until)

        log "Next restart in: $formatted (at midnight UTC+8)"

        # Sleep until target time
        sleep $seconds_until

        # Perform restart
        do_restart

        # Wait a bit before calculating next restart time
        sleep 60
    done
}

setup_cron() {
    # Cron runs at 16:00 UTC = 00:00 UTC+8
    CRON_CMD="0 16 * * * cd $SCRIPT_DIR && ./restart.sh >> $LOG_FILE 2>&1"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "deepseek.*restart"; then
        echo -e "${YELLOW}Existing cron job found. Replacing...${NC}"
        crontab -l 2>/dev/null | grep -v "deepseek.*restart" | crontab -
    fi

    # Add new cron job
    (crontab -l 2>/dev/null; echo "# DeepSeek OCR auto-restart at midnight UTC+8") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -

    echo -e "${GREEN}Cron job installed successfully!${NC}"
    echo ""
    echo "Current cron jobs:"
    crontab -l | grep -A1 "DeepSeek"
    echo ""
    echo "The service will restart daily at:"
    echo "  - 00:00 UTC+8 (midnight Beijing/Shanghai time)"
    echo "  - 16:00 UTC"
    echo ""
    echo "To remove the cron job, run:"
    echo "  crontab -e  (and delete the DeepSeek lines)"
}

stop_daemon() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "Stopping auto-restart daemon (PID: $PID)..."
            kill "$PID" 2>/dev/null
            rm -f "$PID_FILE"
            echo -e "${GREEN}Daemon stopped${NC}"
        else
            echo "Daemon not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        echo "No daemon PID file found"
    fi
}

show_status() {
    echo "=== Auto-restart Status ==="
    echo ""

    # Check daemon status
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo -e "${GREEN}Daemon is running (PID: $PID)${NC}"
        else
            echo -e "${YELLOW}Daemon PID file exists but process not running${NC}"
        fi
    else
        echo "Daemon: Not running"
    fi

    # Check cron job
    if crontab -l 2>/dev/null | grep -q "deepseek.*restart"; then
        echo -e "${GREEN}Cron job: Installed${NC}"
        crontab -l | grep "deepseek.*restart"
    else
        echo "Cron job: Not installed"
    fi

    echo ""

    # Show next restart time
    local seconds_until=$(get_seconds_until_midnight_utc8)
    local formatted=$(format_duration $seconds_until)
    echo "Next midnight UTC+8 in: $formatted"
    echo "Current time (UTC):   $(date -u '+%Y-%m-%d %H:%M:%S')"
    echo "Current time (UTC+8): $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')"
}

# Main
case "${1:-}" in
    --daemon)
        run_daemon
        ;;
    --cron)
        setup_cron
        ;;
    --stop)
        stop_daemon
        ;;
    --status)
        show_status
        ;;
    --help|-h)
        echo "Auto-restart script for DeepSeek OCR PDF Service"
        echo ""
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  (none)     Wait and restart once at next midnight UTC+8"
        echo "  --daemon   Run as daemon, restart every midnight UTC+8"
        echo "  --cron     Setup cron job for daily restart at midnight UTC+8"
        echo "  --stop     Stop the running daemon"
        echo "  --status   Show auto-restart status"
        echo "  --help     Show this help message"
        echo ""
        echo "Time reference:"
        echo "  Midnight UTC+8 = 16:00 UTC = 00:00 Beijing/Shanghai time"
        ;;
    *)
        # Run once at next midnight UTC+8
        echo "=== One-time auto-restart ==="
        local seconds_until=$(get_seconds_until_midnight_utc8)
        local formatted=$(format_duration $seconds_until)
        echo "Waiting for midnight UTC+8..."
        echo "Time until restart: $formatted"
        echo "Press Ctrl+C to cancel"
        echo ""
        sleep $seconds_until
        do_restart
        ;;
esac
