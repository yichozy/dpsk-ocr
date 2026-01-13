#!/bin/bash
set -e

IMAGE_NAME="deepseek-ocr-service"
TAG="latest"

echo "=== Building Docker Image: $IMAGE_NAME:$TAG ==="

# Check if docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker daemon is not running."
    echo "Please start Docker and try again."
    exit 1
fi

# Build the image
echo "Building image..."
docker build --platform linux/amd64 -t $IMAGE_NAME:$TAG .

echo "=== Build Complete ==="
echo ""
echo "To run the container:"
echo "docker run -d --gpus all -p 8000:8000 --env-file .env $IMAGE_NAME:$TAG"
echo ""
echo "To push to Docker Hub (example):"
echo "docker tag $IMAGE_NAME:$TAG enzii/$IMAGE_NAME:$TAG"
echo "docker push enzii/$IMAGE_NAME:$TAG"
