# Use NVIDIA CUDA 11.8 devel image
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_HOME=/usr/local/cuda
ENV TRITON_PTXAS_PATH=/usr/local/cuda/bin/ptxas

# Install system dependencies and Python 3.12
RUN apt-get update && apt-get install -y \
    software-properties-common \
    wget \
    git \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    && rm -rf /var/lib/apt/lists/*

# Set up virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3.12 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip

# Create working directory
WORKDIR /app

# Install PyTorch with CUDA 11.8 support
RUN pip install --no-cache-dir torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu118

# Download and install vllm wheel
RUN wget https://github.com/vllm-project/vllm/releases/download/v0.8.5/vllm-0.8.5+cu118-cp38-abi3-manylinux1_x86_64.whl -O vllm.whl && \
    pip install --no-cache-dir vllm.whl && \
    rm vllm.whl

# Copy requirements
COPY requirements.txt .

# Install dependencies (ignoring system specific issues)
RUN pip install --no-cache-dir -r requirements.txt --ignore-installed dbus-python python-apt || true

# Install additional packages
RUN pip install --no-cache-dir fastapi uvicorn PyMuPDF img2pdf easydict addict

# Install flash-attn
RUN pip install --no-cache-dir flash-attn==2.7.3 --no-build-isolation

# Copy application code
COPY . .

# Create temp directory
RUN mkdir -p tmp/pdf_ocr

# Expose port
EXPOSE 8000

# Run the application
CMD ["python", "serve_pdf.py"]
