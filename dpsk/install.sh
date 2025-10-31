#!/bin/bash

echo "=== DeepSeek OCR Installation ==="
echo ""

# Activate virtual environment
source .venv/bin/activate

# Install PyTorch with CUDA 11.8 support
.venv/bin/pip install torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu118

# Install vllm wheel
.venv/bin/pip install vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl

# Install requirements excluding system-specific packages
.venv/bin/pip install -r requirements.txt --ignore-installed dbus-python python-apt || true

# Install required packages individually (skipping system ones)
.venv/bin/pip install fastapi uvicorn PyMuPDF img2pdf easydict addict

# Install flash-attn
.venv/bin/pip install flash-attn==2.7.3 --no-build-isolation

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Setup your authentication (optional):"
echo "  1. Copy .env.example to .env:"
echo "     cp .env.example .env"
echo ""
echo "  2. Edit .env and set your AUTH_TOKEN"
echo "     nano .env"
echo ""
echo "See README_AUTH.md for more details on authentication."
echo ""