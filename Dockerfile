# Use NVIDIA CUDA 11.8 devel image for building extensions (needed for vllm/triton)
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_HOME=/usr/local/cuda
# Ensure triton can find ptxas
ENV TRITON_PTXAS_PATH=/usr/local/cuda/bin/ptxas

# Install system dependencies
# python3-pip and python3-dev are needed.
# libgl1 and libglib2.0-0 are for opencv compatibility.
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    git \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Upgrade pip to ensure we can handle modern wheels
RUN pip3 install --no-cache-dir --upgrade pip

# Copy requirements first to leverage cache
COPY requirements.txt .

# Install dependencies.
# We include the pytorch index URL to find the specific cu118 wheels if needed.
# We use --no-cache-dir to keep image size down, but for development you might want to remove it.
RUN pip3 install --no-cache-dir -r requirements.txt --extra-index-url https://download.pytorch.org/whl/cu118

# Copy the rest of the application
COPY . .

# Create necessary temporary directories
RUN mkdir -p tmp/pdf_ocr

# Expose the API port
EXPOSE 8000

# Run the application
# We run directly with python3 since serve_pdf.py invokes uvicorn
CMD ["python3", "serve_pdf.py"]
