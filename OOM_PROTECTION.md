# OOM Protection and Auto-Restart Feature

## Overview

This service includes a comprehensive Out of Memory (OOM) protection system that monitors memory usage and automatically triggers a graceful restart when memory thresholds are exceeded, preventing system crashes.

## Features

### 1. **Automatic Memory Monitoring**
- Background thread monitors system memory every 30 seconds
- Tracks both system RAM and GPU memory usage
- Detects when memory usage exceeds the configured threshold

### 2. **Graceful Restart**
- When OOM is detected, the service initiates a graceful shutdown:
  1. Stops accepting new requests
  2. Waits for current processing to complete (60s timeout)
  3. Clears GPU memory
  4. Forces garbage collection
  5. Restarts the service automatically

### 3. **Enhanced Health Check**
The `/health` endpoint now includes detailed memory information:

```bash
curl http://localhost:8000/health
```

Response:
```json
{
  "status": "healthy",
  "model_loaded": true,
  "memory": {
    "system_memory_percent": 65.2,
    "system_memory_available_gb": 14.5,
    "system_memory_total_gb": 32.0,
    "process_memory_gb": 3.2,
    "process_memory_percent": 10.1,
    "gpu_memory_allocated_gb": 2.1,
    "gpu_memory_reserved_gb": 4.0
  },
  "oom_protection_enabled": true,
  "memory_threshold_percent": 90.0
}
```

### 4. **Memory Monitoring Script**

Use the provided script to monitor memory usage in real-time:

```bash
./monitor_memory.sh
```

Output:
```
==========================================
  OCR Service Memory Monitor
==========================================

📡 Service PID: 12345

[2026-03-19 10:30:00] Process: 3.20GB | System: 65.2% | GPU: 2.1 GB / 24.0 GB
[2026-03-19 10:30:05] Process: 3.25GB | System: 66.1% | GPU: 2.1 GB / 24.0 GB
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OOM_RESTART_ENABLED` | `true` | Enable/disable OOM protection |
| `OOM_MEMORY_THRESHOLD` | `90` | Memory threshold percentage (0-100) |

### Configuration Example (.env)

```bash
# Enable OOM protection (default: true)
OOM_RESTART_ENABLED=true

# Set memory threshold to 85% for more aggressive protection
OOM_MEMORY_THRESHOLD=85
```

## How It Works

### 1. Background Monitoring
A dedicated background thread checks memory every 30 seconds:

```python
# In serve_pdf.py
def monitor_memory_loop():
    # Checks:
    # - System memory usage
    # - Process memory usage
    # - GPU memory usage
    # - Triggers restart if threshold exceeded
```

### 2. Pre-Processing Check
Before processing each PDF:
- Checks if system is already in OOM condition
- Rejects processing if memory is critically low
- Triggers restart if needed

### 3. Post-Processing Check
After processing each PDF:
- Verifies memory hasn't exceeded threshold
- Triggers restart if memory is high

### 4. Exception Handling
Catches specific OOM exceptions:
- `torch.cuda.OutOfMemoryError` - GPU OOM
- `MemoryError` - System RAM OOM
- Automatically triggers graceful restart

## Testing OOM Protection

### Test 1: Monitor Memory
```bash
# Watch memory usage
./monitor_memory.sh

# In another terminal, process a large PDF
curl -X POST http://localhost:8000/process_pdf \
  -H "Authorization: Bearer your-token" \
  -F "file=@large.pdf"
```

### Test 2: Simulate High Memory
You can temporarily lower the threshold to test the restart mechanism:

```bash
# In .env
OOM_MEMORY_THRESHOLD=30  # Will trigger restart at 30%

# Restart service
docker-compose restart
```

### Test 3: Check Health Endpoint
```bash
watch -n 5 'curl -s http://localhost:8000/health | jq'
```

## Troubleshooting

### Service Keeps Restarting
**Problem:** Service enters restart loop

**Solutions:**
1. Increase `OOM_MEMORY_THRESHOLD`
2. Reduce `BATCH_SIZE` in serve_pdf.py
3. Reduce `MAX_CONCURRENCY` in config.py
4. Process smaller PDFs

### Memory Still Too High
**Problem:** Even with protections, memory usage is too high

**Solutions:**
1. Reduce DPI in `pdf_to_images_high_quality()` (default: 144)
2. Reduce `BATCH_SIZE` in `process_pdf_internal()` (default: 10)
3. Reduce `NUM_WORKERS` in config.py
4. Limit concurrent requests

### Monitoring Not Working
**Problem:** Memory monitor not starting

**Check:**
```bash
# Check logs
docker logs <container> | grep -i "memory monitor"

# Verify psutil is installed
python -c "import psutil; print(psutil.__version__)"
```

## Log Messages

### Normal Operation
```
✅ Memory monitor started (threshold: 90%, interval: 30s)
```

### OOM Detected
```
⚠️  OOM CONDITION DETECTED:
   System Memory: 91.2%
   Process Memory: 18.50 GB
   Available Memory: 2.80 GB
🔄 INITIATING GRACEFUL RESTART DUE TO OOM CONDITION
```

### Processing with OOM
```
❌ System OOM condition detected before processing: 92.5% memory usage
❌ GPU OOM: CUDA out of memory
```

## Best Practices

1. **Monitor Regularly**: Use `monitor_memory.sh` during operation
2. **Set Appropriate Threshold**: 90% is default; adjust based on your system
3. **Process Smaller Batches**: If you have memory issues, reduce BATCH_SIZE
4. **Check Health Endpoint**: Use `/health` to monitor memory trends
5. **Review Logs**: Check for OOM warnings to identify problematic files

## Performance Impact

- **Memory overhead**: ~5-10 MB for monitoring thread
- **CPU overhead**: Negligible (<0.1% CPU)
- **Restart time**: ~5-10 seconds for graceful shutdown

## Support

For issues or questions about OOM protection:
1. Check logs for OOM warnings
2. Use `/health` endpoint to monitor memory
3. Review configuration in `.env` file
4. Adjust threshold based on your system capacity
