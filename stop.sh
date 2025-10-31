#!/bin/bash

# Configuration
SERVICE_NAME="DeepSeek OCR PDF Service"
PID_FILE="/tmp/deepseek_ocr.pid"
LOG_FILE="/tmp/deepseek_ocr.log"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Stopping $SERVICE_NAME ==="
echo ""

STOPPED=false

# Try to stop using PID file first
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    echo "Found PID file: $PID"

    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Stopping process $PID..."
        kill "$PID" 2>/dev/null

        # Wait for graceful shutdown
        MAX_WAIT=10
        WAITED=0
        while [ $WAITED -lt $MAX_WAIT ]; do
            if ! ps -p "$PID" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Process stopped gracefully${NC}"
                STOPPED=true
                break
            fi
            sleep 1
            WAITED=$((WAITED + 1))
        done

        # Force kill if still running
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "Process still running, forcing termination..."
            kill -9 "$PID" 2>/dev/null
            sleep 1
            if ! ps -p "$PID" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Process force-stopped${NC}"
                STOPPED=true
            fi
        fi
    else
        echo "Process $PID is not running"
    fi

    # Clean up PID file
    rm -f "$PID_FILE"
fi

# Fallback: Kill any remaining serve_pdf.py processes
echo ""
echo "Checking for any remaining serve_pdf.py processes..."
if pgrep -f "python.*serve_pdf.py" > /dev/null; then
    echo "Found remaining processes, stopping them..."
    pkill -f "python.*serve_pdf.py"
    sleep 2

    # Force kill if still running
    if pgrep -f "python.*serve_pdf.py" > /dev/null; then
        echo "Forcing termination of remaining processes..."
        pkill -9 -f "python.*serve_pdf.py"
        sleep 1
    fi

    if ! pgrep -f "python.*serve_pdf.py" > /dev/null; then
        echo -e "${GREEN}✓ All processes stopped${NC}"
        STOPPED=true
    else
        echo -e "${RED}✗ Failed to stop some processes${NC}"
    fi
else
    echo "No serve_pdf.py processes found"
    if [ "$STOPPED" = false ]; then
        echo -e "${YELLOW}Service was not running${NC}"
    fi
fi

# Display GPU status
echo ""
echo "GPU Memory Status:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | \
        awk -F', ' '{printf "  GPU: %s\n  Memory: %s MB / %s MB (%.1f%%)\n  Utilization: %s%%\n", $1, $2, $3, ($2/$3)*100, $4}'
else
    echo "  nvidia-smi not available"
fi

echo ""
if [ "$STOPPED" = true ]; then
    echo -e "${GREEN}Service stopped successfully. GPU memory has been freed.${NC}"
else
    echo -e "${YELLOW}Service cleanup completed.${NC}"
fi

# Show log location if it exists
if [ -f "$LOG_FILE" ]; then
    echo ""
    echo "Service logs available at: $LOG_FILE"
fi
echo ""
