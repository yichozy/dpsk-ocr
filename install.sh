#!/bin/bash

echo "=== DeepSeek OCR Installation ==="

# Function to install Python 3.12
install_python() {
    echo "Python 3.12 not found. Attempting to install..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Python 3.12 is missing. Please run this script with sudo to install it."
        echo "Try: sudo ./install.sh"
        exit 1
    fi

    apt-get update
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update
    apt-get install -y python3.12 python3.12-venv python3.12-dev
}

# Check for Python 3.12
if ! command -v python3.12 &> /dev/null; then
    install_python
fi

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3.12 -m venv .venv
fi

# Use the virtual environment's pip
PIP=".venv/bin/pip"
PYTHON=".venv/bin/python"

echo "Using Python: $($PYTHON --version)"

# Install PyTorch with CUDA 11.8 support
echo "Installing PyTorch..."
$PIP install torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu118

# Download and install vllm wheel
echo "Checking vllm wheel..."
WHEEL_NAME="vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl"
WHEEL_PATH="install/$WHEEL_NAME"

if [ ! -f "$WHEEL_PATH" ]; then
    echo "Downloading vllm wheel..."
    mkdir -p install
    wget https://github.com/vllm-project/vllm/releases/download/v0.8.5/$WHEEL_NAME -P install/
fi

echo "Installing vllm..."
$PIP install "$WHEEL_PATH"

# Install requirements excluding system-specific packages
echo "Installing requirements..."
$PIP install -r requirements.txt --ignore-installed dbus-python python-apt || true

# Install required packages individually (skipping system ones)
$PIP install fastapi uvicorn PyMuPDF img2pdf easydict addict

# Install flash-attn
echo "Installing flash-attn..."
$PIP install flash-attn==2.7.3 --no-build-isolation

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


mkdir -p tmp/pdf_ocr