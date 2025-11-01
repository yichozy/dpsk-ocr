#!/bin/bash

# restart.sh - Restart the DeepSeek OCR PDF Service
# Usage: ./restart.sh

set -e

echo "=== Restarting DeepSeek OCR PDF Service ==="
echo ""

# Stop the service
if [ -f "./stop.sh" ]; then
    echo "Stopping service..."
    ./stop.sh
    echo ""
else
    echo "Error: stop.sh not found"
    exit 1
fi

# Wait a moment for cleanup
sleep 2

# Start the service
if [ -f "./run.sh" ]; then
    echo "Starting service..."
    ./run.sh
else
    echo "Error: run.sh not found"
    exit 1
fi
