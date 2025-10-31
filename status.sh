#!/bin/bash

# Configuration
SERVICE_NAME="DeepSeek OCR PDF Service"
PID_FILE="/tmp/deepseek_ocr.pid"
LOG_FILE="/tmp/deepseek_ocr.log"
PORT=8000

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== $SERVICE_NAME Status ==="
echo ""

# Check if PID file exists
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    echo -e "${BLUE}PID File:${NC} $PID_FILE (PID: $PID)"

    # Check if process is running
    if ps -p "$PID" > /dev/null 2>&1; then
        # Verify it's our process
        if ps -p "$PID" -o cmd= | grep -q "serve_pdf.py"; then
            echo -e "${GREEN}✓ Service is RUNNING${NC}"
            echo ""

            # Show process details
            echo "Process Information:"
            ps -p "$PID" -o pid,ppid,%cpu,%mem,etime,cmd --no-headers | \
                awk '{printf "  PID: %s\n  Parent PID: %s\n  CPU: %s%%\n  Memory: %s%%\n  Uptime: %s\n  Command: %s\n", $1, $2, $3, $4, $5, substr($0, index($0,$6))}'
            echo ""

            # Check port status
            if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
                echo -e "${GREEN}✓ Listening on port $PORT${NC}"
            else
                echo -e "${YELLOW}⚠ Not listening on port $PORT (may be initializing)${NC}"
            fi

        else
            echo -e "${RED}✗ PID exists but not running serve_pdf.py${NC}"
        fi
    else
        echo -e "${RED}✗ Process not running (stale PID file)${NC}"
    fi
else
    echo -e "${YELLOW}No PID file found${NC}"

    # Check for running processes anyway
    if pgrep -f "python.*serve_pdf.py" > /dev/null; then
        echo -e "${YELLOW}⚠ Found serve_pdf.py process(es) running without PID file${NC}"
        echo ""
        echo "Running processes:"
        ps aux | grep "[p]ython.*serve_pdf.py" | awk '{printf "  PID: %s, CPU: %s%%, MEM: %s%%\n", $2, $3, $4}'
    else
        echo -e "${RED}✗ Service is NOT running${NC}"
    fi
fi

echo ""

# Check GPU status
echo "GPU Status:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | \
        awk -F', ' '{printf "  GPU: %s\n  Memory: %s MB / %s MB (%.1f%%)\n  Utilization: %s%%\n  Temperature: %s°C\n", $1, $2, $3, ($2/$3)*100, $4, $5}'
else
    echo "  nvidia-smi not available"
fi

echo ""

# Check authentication status
echo "Authentication:"
if [ -f ".env" ]; then
    if grep -q "^AUTH_TOKEN=" .env && ! grep -q "^AUTH_TOKEN=your-secret-token-here" .env && ! grep -q "^#AUTH_TOKEN=" .env; then
        echo -e "  ${GREEN}✓ Enabled (AUTH_TOKEN configured)${NC}"
    else
        echo -e "  ${YELLOW}⚠ Disabled (AUTH_TOKEN not configured)${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ Disabled (no .env file)${NC}"
fi

echo ""

# Show recent log entries if log file exists
if [ -f "$LOG_FILE" ]; then
    echo "Recent Log Entries (last 5 lines):"
    echo "─────────────────────────────────────"
    tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    echo "─────────────────────────────────────"
    echo "Full log: $LOG_FILE"
else
    echo "No log file found"
fi

echo ""

# Show service URLs if running
if [ -f "$PID_FILE" ] && ps -p "$(cat $PID_FILE)" > /dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        echo "Service URLs:"
        echo "  • Health: http://localhost:$PORT/health"
        echo "  • Docs: http://localhost:$PORT/docs"
        echo "  • API: http://localhost:$PORT/"
        echo ""
    fi
fi

echo "Commands:"
echo "  • Start: ./run.sh"
echo "  • Stop: ./stop.sh"
echo "  • Logs: tail -f $LOG_FILE"
echo ""
