#!/bin/bash

# Configuration
SERVICE_NAME="DeepSeek OCR PDF Service"
PYTHON_BIN=".venv/bin/python"
SCRIPT_NAME="serve_pdf.py"
PID_FILE="/tmp/deepseek_ocr.pid"
LOG_FILE="/tmp/deepseek_ocr.log"
PORT=8000

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== $SERVICE_NAME ==="
echo ""

# Check if virtual environment exists
if [ ! -f "$PYTHON_BIN" ]; then
    echo -e "${RED}Error: Virtual environment not found at .venv/${NC}"
    echo "Please run ./install/install.sh first"
    exit 1
fi

# Check if serve_pdf.py exists
if [ ! -f "$SCRIPT_NAME" ]; then
    echo -e "${RED}Error: $SCRIPT_NAME not found${NC}"
    exit 1
fi

# Function to check if service is running
is_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            # Check if it's actually our process
            if ps -p "$PID" -o cmd= | grep -q "$SCRIPT_NAME"; then
                return 0
            fi
        fi
        # PID file exists but process is not running
        rm -f "$PID_FILE"
    fi
    return 1
}

# Check if service is already running
if is_running; then
    PID=$(cat "$PID_FILE")
    echo -e "${YELLOW}Service is already running (PID: $PID)${NC}"
    echo ""
    echo "To view logs: tail -f $LOG_FILE"
    echo "To stop: ./stop.sh"
    echo ""

    # Show service status
    echo "Service Status:"
    ps -p "$PID" -o pid,ppid,%cpu,%mem,etime,cmd --no-headers
    echo ""

    # Check if port is listening
    if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        echo -e "${GREEN}Service is listening on port $PORT${NC}"
    else
        echo -e "${YELLOW}Warning: Service running but not listening on port $PORT yet${NC}"
        echo "It may still be initializing..."
    fi

    exit 0
fi

# Check if port is already in use
if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
    echo -e "${RED}Error: Port $PORT is already in use${NC}"
    echo "Please stop the existing service or use a different port"
    exit 1
fi

# Check for .env file
if [ -f ".env" ]; then
    echo -e "${GREEN}Found .env file - Authentication will be enabled${NC}"
    if grep -q "^AUTH_TOKEN=" .env && ! grep -q "^AUTH_TOKEN=your-secret-token-here" .env && ! grep -q "^#AUTH_TOKEN=" .env; then
        echo -e "${GREEN}AUTH_TOKEN is configured${NC}"
    else
        echo -e "${YELLOW}Warning: AUTH_TOKEN not properly configured in .env${NC}"
        echo "Service will run without authentication"
    fi
else
    echo -e "${YELLOW}No .env file found - Service will run without authentication${NC}"
    echo "For production use, create .env with AUTH_TOKEN"
fi

echo ""
echo "Starting $SERVICE_NAME..."
echo "Log file: $LOG_FILE"
echo ""

# Start the service in background
nohup $PYTHON_BIN $SCRIPT_NAME > "$LOG_FILE" 2>&1 &
PID=$!

# Save PID to file
echo "$PID" > "$PID_FILE"

# Wait a moment to check if process started successfully
sleep 2

if is_running; then
    echo -e "${GREEN}✓ Service started successfully${NC}"
    echo "  PID: $PID"
    echo "  Port: $PORT"
    echo ""

    # Wait for service to be ready (check for port listening)
    echo "Waiting for service to be ready..."
    MAX_WAIT=60
    WAITED=0
    while [ $WAITED -lt $MAX_WAIT ]; do
        if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
            echo -e "${GREEN}✓ Service is ready and listening on port $PORT${NC}"
            break
        fi

        # Check if process is still running
        if ! is_running; then
            echo -e "${RED}✗ Service stopped unexpectedly${NC}"
            echo ""
            echo "Last 20 lines of log:"
            tail -20 "$LOG_FILE"
            rm -f "$PID_FILE"
            exit 1
        fi

        sleep 1
        WAITED=$((WAITED + 1))

        if [ $((WAITED % 10)) -eq 0 ]; then
            echo "  Still initializing... (${WAITED}s elapsed)"
        fi
    done

    if [ $WAITED -ge $MAX_WAIT ]; then
        echo -e "${YELLOW}Warning: Service started but not responding on port $PORT after ${MAX_WAIT}s${NC}"
        echo "Check logs for more details: tail -f $LOG_FILE"
    fi

    echo ""
    echo "Service URLs:"
    echo "  • Health check: http://localhost:$PORT/health"
    echo "  • API docs: http://localhost:$PORT/docs"
    echo "  • Base URL: http://localhost:$PORT/"
    echo ""
    echo "Useful commands:"
    echo "  • View logs: tail -f $LOG_FILE"
    echo "  • Stop service: ./stop.sh"
    echo "  • Check status: ps -p $PID"
    echo ""

else
    echo -e "${RED}✗ Failed to start service${NC}"
    echo ""
    echo "Last 20 lines of log:"
    tail -20 "$LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
fi
