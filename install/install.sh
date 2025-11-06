#!/bin/bash

echo "=== DeepSeek OCR Installation ==="
echo ""


# Install PyTorch with CUDA 11.8 support
pip install torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu118

# Download and install vllm wheel
echo "Downloading vllm wheel..."

wget https://github.com/vllm-project/vllm/releases/download/v0.8.5/vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl -P /tmp/

pip install /tmp/vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl

rm /tmp/vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl

# Install requirements excluding system-specific packages
pip install -r ../requirements.txt --ignore-installed dbus-python python-apt || true

# Install required packages individually (skipping system ones)
pip install fastapi uvicorn PyMuPDF img2pdf easydict addict

# Install flash-attn
pip install flash-attn==2.7.3 --no-build-isolation

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