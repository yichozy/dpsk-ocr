#!/bin/bash
# Memory monitoring script for the OCR service
# Usage: ./monitor_memory.sh

echo "=========================================="
echo "  OCR Service Memory Monitor"
echo "=========================================="
echo ""

# Check if service is running
if ! pgrep -f "serve_pdf.py" > /dev/null; then
    echo "❌ Service is not running"
    exit 1
fi

# Get the process ID
PID=$(pgrep -f "serve_pdf.py" | head -1)
echo "📡 Service PID: $PID"
echo ""

# Monitor memory
while true; do
    if ! ps -p $PID > /dev/null 2>&1; then
        echo "❌ Service has stopped"
        break
    fi

    # Get memory usage
    MEM_USAGE=$(ps -p $PID -o rss= | awk '{printf "%.2f", $1/1024/1024}')
    MEM_PERCENT=$(ps -p $PID -o rss= | awk '{printf "%.1f", ($1/1024/1024)*100/}' $(free | grep Mem | awk '{print $2}') 2>/dev/null || echo "N/A")

    # Get system memory
    SYS_MEM=$(free | grep Mem | awk '{printf "%.1f", ($3/$2)*100}')

    # Get GPU memory if available
    if command -v nvidia-smi &> /dev/null; then
        GPU_MEM=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | awk '{printf "%.1f GB / %.1f GB", $1/1024, $2/1024}')
    else
        GPU_MEM="N/A"
    fi

    # Timestamp
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Display
    echo "[$TIMESTAMP] Process: ${MEM_USAGE}GB | System: ${SYS_MEM}% | GPU: $GPU_MEM"

    # Warning if high
    MEM_VAL=$(echo $SYS_MEM | cut -d'.' -f1)
    if [ "$MEM_VAL" -ge 85 ]; then
        echo "⚠️  WARNING: High memory usage!"
    fi

    sleep 5
done
