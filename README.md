# DeepSeek OCR PDF Service

Complete OCR service for PDF documents with layout detection, powered by DeepSeek-OCR and vLLM.

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Service Management](#service-management)
- [Authentication](#authentication)
- [API Usage](#api-usage)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

---

## Quick Start

### Prerequisites

- NVIDIA GPU with CUDA 11.8 support
- Python 3.12 virtual environment at `.venv/`
- At least 8GB GPU memory

### Installation

1. Run the installation script:
```bash
./install.sh
```

This will install:
- PyTorch 2.6.0 with CUDA 11.8
- vLLM 0.8.5
- flash-attn 2.7.3
- All required dependencies

### Start the Service

```bash
./run.sh
```

The service will be available at `http://localhost:8000`

### Check Status

```bash
./status.sh
```

### Stop the Service

```bash
./stop.sh
```

---

## Installation

### System Requirements

**Hardware:**
- NVIDIA GPU (tested on A40 with 44GB memory)
- CUDA 11.8 compatible GPU
- Minimum 8GB GPU memory

**Software:**
- Ubuntu 24.04 (or compatible)
- Python 3.12
- CUDA 11.8
- nvidia-smi

### Installation Steps

1. **Create virtual environment** (if not exists):
```bash
python3.12 -m venv .venv
```

2. **Run installation script**:
```bash
chmod +x install.sh
./install.sh
```

The script will:
- Activate virtual environment
- Install PyTorch with CUDA 11.8 support
- Install vLLM wheel
- Install all dependencies
- Install flash-attn
- Display authentication setup instructions

3. **Verify installation**:
```bash
.venv/bin/python -c "import torch, vllm; print(f'PyTorch: {torch.__version__}, vLLM: {vllm.__version__}')"
```

---

## Service Management

Three scripts provide complete service lifecycle management:

### run.sh - Start Service

```bash
./run.sh
```

**Features:**
- Checks if service is already running (prevents duplicates)
- Validates environment and port availability
- Creates PID file for reliable tracking
- Starts service in background with logging
- Waits for service to be ready (up to 60 seconds)
- Displays service URLs and status
- Checks authentication configuration

**Output:**
```
=== DeepSeek OCR PDF Service ===

✓ Service started successfully
  PID: 12345
  Port: 8000

Service URLs:
  • Health check: http://localhost:8000/health
  • API docs: http://localhost:8000/docs
  • Base URL: http://localhost:8000/

Useful commands:
  • View logs: tail -f /tmp/deepseek_ocr.log
  • Stop service: ./stop.sh
```

### status.sh - Check Status

```bash
./status.sh
```

**Displays:**
- Process status (PID, uptime, CPU/memory usage)
- GPU metrics (memory, utilization, temperature)
- Authentication status
- Recent log entries (last 5 lines)
- Service URLs (if running)

### stop.sh - Stop Service

```bash
./stop.sh
```

**Features:**
- Graceful shutdown (SIGTERM, waits 10 seconds)
- Force-kill if necessary (SIGKILL)
- Cleans up PID file
- Stops orphaned processes
- Displays GPU memory status
- Shows log file location

### Common Workflows

**Start and monitor:**
```bash
./run.sh
tail -f /tmp/deepseek_ocr.log
```

**Restart service:**
```bash
./stop.sh && ./run.sh
```

**Check if running:**
```bash
./status.sh | grep -q "Service is RUNNING" && echo "Running" || echo "Not running"
```

### File Locations

| File | Location | Purpose |
|------|----------|---------|
| PID file | `/tmp/deepseek_ocr.pid` | Process ID tracking |
| Log file | `/tmp/deepseek_ocr.log` | Service logs |
| Config | `.env` | Authentication token |

---

## Authentication

The service supports token-based authentication using Bearer tokens.

### Setup Authentication

1. **Create `.env` file**:
```bash
cp .env.example .env
```

2. **Generate a secure token**:
```bash
# Using Python
python -c "import secrets; print(secrets.token_hex(32))"

# Using OpenSSL
openssl rand -hex 32
```

3. **Edit `.env` and set your token**:
```bash
AUTH_TOKEN=your-generated-token-here
```

4. **Restart service** (if running):
```bash
./stop.sh && ./run.sh
```

### Disable Authentication

To disable authentication (development only):
- Remove or comment out `AUTH_TOKEN` in `.env`, or
- Don't create a `.env` file

### Protected Endpoints

When `AUTH_TOKEN` is set, these endpoints require authentication:

- `POST /process_pdf` - Upload and process PDF
- `GET /result/{job_id}/markdown` - Get markdown output
- `GET /result/{job_id}/markdown_det` - Get markdown with detections
- `GET /result/{job_id}/layout_pdf` - Download layout PDF
- `GET /result/{job_id}/images` - List extracted images
- `GET /result/{job_id}/images/{image_name}` - Get specific image
- `DELETE /result/{job_id}` - Delete job files

### Public Endpoints

These endpoints are always accessible without authentication:

- `GET /` - API information
- `GET /health` - Health check

---

## API Usage

### Using curl

**Upload and process PDF:**
```bash
curl -X POST "http://localhost:8000/process_pdf" \
  -H "Authorization: Bearer your-token-here" \
  -F "file=@document.pdf"
```

**Response:**
```json
{
  "job_id": "abc123-def456-789...",
  "status": "completed",
  "message": "PDF processed successfully"
}
```

**Get markdown result:**
```bash
curl -X GET "http://localhost:8000/result/{job_id}/markdown" \
  -H "Authorization: Bearer your-token-here"
```

**Download layout PDF:**
```bash
curl -X GET "http://localhost:8000/result/{job_id}/layout_pdf" \
  -H "Authorization: Bearer your-token-here" \
  -o layout.pdf
```

**Health check (no auth required):**
```bash
curl http://localhost:8000/health
```

### Using Python

```python
import requests

# Configure
API_URL = "http://localhost:8000"
AUTH_TOKEN = "your-token-here"
headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}

# Upload PDF
with open("document.pdf", "rb") as f:
    files = {"file": f}
    response = requests.post(
        f"{API_URL}/process_pdf",
        headers=headers,
        files=files
    )
    result = response.json()
    job_id = result["job_id"]
    print(f"Job ID: {job_id}")

# Get markdown result
response = requests.get(
    f"{API_URL}/result/{job_id}/markdown",
    headers=headers
)
markdown_content = response.json()["content"]
print(markdown_content)

# Download layout PDF
response = requests.get(
    f"{API_URL}/result/{job_id}/layout_pdf",
    headers=headers
)
with open("layout.pdf", "wb") as f:
    f.write(response.content)

# Clean up
requests.delete(f"{API_URL}/result/{job_id}", headers=headers)
```

### Using JavaScript

```javascript
const API_URL = "http://localhost:8000";
const AUTH_TOKEN = "your-token-here";

// Upload PDF
const formData = new FormData();
formData.append("file", pdfFile);

const uploadResponse = await fetch(`${API_URL}/process_pdf`, {
    method: "POST",
    headers: {
        "Authorization": `Bearer ${AUTH_TOKEN}`
    },
    body: formData
});

const { job_id } = await uploadResponse.json();

// Get markdown result
const resultResponse = await fetch(
    `${API_URL}/result/${job_id}/markdown`,
    {
        headers: {
            "Authorization": `Bearer ${AUTH_TOKEN}`
        }
    }
);

const { content } = await resultResponse.json();
console.log(content);
```

### API Endpoints Reference

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/` | No | API information |
| GET | `/health` | No | Health check |
| POST | `/process_pdf` | Yes* | Upload and process PDF |
| GET | `/result/{job_id}/markdown` | Yes* | Get markdown output |
| GET | `/result/{job_id}/markdown_det` | Yes* | Get markdown with detections |
| GET | `/result/{job_id}/layout_pdf` | Yes* | Download layout PDF |
| GET | `/result/{job_id}/images` | Yes* | List extracted images |
| GET | `/result/{job_id}/images/{image_name}` | Yes* | Get specific image |
| DELETE | `/result/{job_id}` | Yes* | Delete job files |

*Auth required only if `AUTH_TOKEN` is configured in `.env`

**Interactive API Documentation:**
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

---

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# Authentication Token
# Set this to enable token-based authentication
# If not set, API will be accessible without authentication
AUTH_TOKEN=your-secret-token-here
```

### Service Configuration

Edit `config.py` to modify:

- `MODEL_PATH` - Model location
- `PROMPT` - OCR prompt template
- `SKIP_REPEAT` - Skip repeated content
- `MAX_CONCURRENCY` - Max concurrent requests
- `NUM_WORKERS` - Number of worker threads
- `CROP_MODE` - Image cropping mode

### Model Configuration

The service uses DeepSeek-OCR model with these settings:

- **Model**: `deepseek-ai/DeepSeek-OCR`
- **Max sequence length**: 8192 tokens
- **GPU memory utilization**: 90%
- **Tensor parallel size**: 1
- **Block size**: 256

---

## Troubleshooting

### Service Won't Start

**Check if already running:**
```bash
./status.sh
```

**Check for port conflicts:**
```bash
netstat -tuln | grep 8000
lsof -i :8000
```

**Check logs:**
```bash
tail -100 /tmp/deepseek_ocr.log
```

**Check virtual environment:**
```bash
ls -la .venv/bin/python
.venv/bin/python --version
```

### Service Won't Stop

**Force stop:**
```bash
./stop.sh
# If that doesn't work:
pkill -9 -f "serve_pdf.py"
rm -f /tmp/deepseek_ocr.pid
```

### Authentication Issues

**401 Unauthorized Error:**
- Verify token matches `AUTH_TOKEN` in `.env`
- Check "Bearer " prefix in Authorization header
- Ensure `.env` file is loaded (restart service)

**Disable authentication:**
```bash
# Comment out or remove AUTH_TOKEN from .env
sed -i 's/^AUTH_TOKEN=/#AUTH_TOKEN=/' .env
./stop.sh && ./run.sh
```

### GPU Memory Issues

**Check GPU status:**
```bash
nvidia-smi
```

**Free GPU memory:**
```bash
./stop.sh
# If memory not released:
pkill -9 -f "python.*serve_pdf"
nvidia-smi
```

**Reduce memory usage:**
Edit `serve_pdf.py`:
```python
llm = LLM(
    ...
    gpu_memory_utilization=0.7,  # Reduce from 0.9
    max_num_seqs=4,  # Reduce from MAX_CONCURRENCY
)
```

### Import Errors

**Missing modules:**
```bash
# Reinstall dependencies
.venv/bin/pip install -r requirements.txt
.venv/bin/pip install PyMuPDF img2pdf easydict addict
```

**Check Python version:**
```bash
.venv/bin/python --version  # Should be 3.12.x
```

### Log Management

**Log file too large:**
```bash
./stop.sh
mv /tmp/deepseek_ocr.log /tmp/deepseek_ocr.log.old
./run.sh
```

**Monitor logs:**
```bash
# Real-time
tail -f /tmp/deepseek_ocr.log

# Last 50 lines
tail -50 /tmp/deepseek_ocr.log

# Search for errors
grep -i error /tmp/deepseek_ocr.log
```

### Stale PID File

```bash
rm -f /tmp/deepseek_ocr.pid
./status.sh  # Verify clean state
./run.sh     # Start fresh
```

---

## Advanced Topics

### Systemd Integration

Create `/etc/systemd/system/deepseek-ocr.service`:

```ini
[Unit]
Description=DeepSeek OCR PDF Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/dpsk
ExecStart=/root/dpsk/.venv/bin/python /root/dpsk/serve_pdf.py
ExecStop=/root/dpsk/stop.sh
Restart=on-failure
RestartSec=10s
StandardOutput=append:/tmp/deepseek_ocr.log
StandardError=append:/tmp/deepseek_ocr.log

[Install]
WantedBy=multi-user.target
```

**Enable and start:**
```bash
systemctl daemon-reload
systemctl enable deepseek-ocr
systemctl start deepseek-ocr
systemctl status deepseek-ocr
```

### Automated Health Checks

**Cron job (check every 5 minutes):**
```bash
# Add to crontab
*/5 * * * * /root/dpsk/status.sh | grep -q "NOT running" && /root/dpsk/run.sh
```

**Monitoring script:**
```bash
#!/bin/bash
# check_service.sh

if ! /root/dpsk/status.sh | grep -q "Service is RUNNING"; then
    echo "ALERT: Service is DOWN" | mail -s "Service Alert" admin@example.com
    /root/dpsk/run.sh
fi
```

### Performance Tuning

**Adjust concurrency:**
Edit `config.py`:
```python
MAX_CONCURRENCY = 8  # Adjust based on GPU memory
NUM_WORKERS = 4      # Adjust based on CPU cores
```

**Optimize GPU usage:**
Edit `serve_pdf.py`:
```python
llm = LLM(
    ...
    gpu_memory_utilization=0.85,  # Adjust (0.7-0.95)
    max_num_seqs=MAX_CONCURRENCY,
    tensor_parallel_size=1,        # Increase for multi-GPU
)
```

**Enable CUDA graphs for better performance:**
```python
llm = LLM(
    ...
    enforce_eager=False,  # Use CUDA graphs
)
```

### Security Best Practices

1. **Use strong tokens** (at least 32 characters)
2. **Rotate tokens regularly**
3. **Use HTTPS in production** (reverse proxy with nginx/caddy)
4. **Limit token sharing** to authorized users only
5. **Never commit `.env` to version control**
6. **Set up firewall rules** to restrict access
7. **Monitor access logs** for suspicious activity

### Reverse Proxy Setup (nginx)

```nginx
server {
    listen 443 ssl http2;
    server_name ocr.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Increase timeout for long processing
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;

        # Increase max body size for large PDFs
        client_max_body_size 100M;
    }
}
```

---

## Project Structure

```
/root/dpsk/
├── serve_pdf.py              # Main service application
├── pdf_utils.py              # PDF conversion utilities
├── processing_utils.py       # Image processing utilities
├── deepseek_ocr.py           # DeepSeek OCR model
├── config.py                 # Configuration
├── requirements.txt          # Python dependencies
├── install.sh                # Installation script
├── run.sh                    # Start service script
├── stop.sh                   # Stop service script
├── status.sh                 # Status check script
├── .env.example              # Environment template
├── .env                      # Your configuration (not in git)
├── .venv/                    # Virtual environment
├── process/                  # Processing modules
│   ├── ngram_norepeat.py
│   └── image_process.py
├── deepencoder/              # Encoder modules
│   ├── clip_sdpa.py
│   └── sam_vary_sdpa.py
└── README.md                 # This file
```

---

## Technical Details

**Environment:**
- Virtual environment: `.venv/`
- Python: 3.12
- PyTorch: 2.6.0 with CUDA 11.8
- vLLM: 0.8.5
- Model: DeepSeek-OCR

**GPU Support:**
- Tested on NVIDIA A40 (44GB)
- Requires CUDA 11.8
- Uses 90% GPU memory by default

**Features:**
- PDF to image conversion (high quality, 144 DPI)
- OCR with layout detection
- Bounding box extraction and visualization
- Image region extraction
- Markdown output with/without layout annotations
- Token-based authentication
- RESTful API with OpenAPI docs
- Concurrent request processing

---

## Support and Contribution

**Check Status:**
```bash
./status.sh
```

**View Logs:**
```bash
tail -f /tmp/deepseek_ocr.log
```

**Report Issues:**
Include in your report:
- Service status output
- Last 50 lines of log
- GPU status (`nvidia-smi`)
- Error messages

---

## License

This service uses DeepSeek-OCR model. Please refer to the model's license for usage terms.

---

## Quick Reference

### Common Commands

```bash
# Installation
./install.sh

# Service Management
./run.sh          # Start service
./stop.sh         # Stop service
./status.sh       # Check status

# Logs
tail -f /tmp/deepseek_ocr.log       # Follow logs
grep error /tmp/deepseek_ocr.log    # Find errors

# API Testing
curl http://localhost:8000/health   # Health check
curl http://localhost:8000/docs     # API documentation

# GPU Monitoring
nvidia-smi                           # Check GPU status
watch -n1 nvidia-smi                 # Monitor GPU continuously
```

### Environment Setup

```bash
# Create .env
cp .env.example .env

# Generate token
python -c "import secrets; print(secrets.token_hex(32))"

# Edit .env
nano .env
```

### Troubleshooting Commands

```bash
# Check if running
ps aux | grep serve_pdf.py

# Check port
netstat -tuln | grep 8000
lsof -i :8000

# Force stop all
pkill -9 -f serve_pdf.py
rm -f /tmp/deepseek_ocr.pid

# Clean restart
./stop.sh && rm -f /tmp/deepseek_ocr.log && ./run.sh
```

---

**Version:** 1.0.0
**Last Updated:** 2025-10-31
