#!/bin/bash

echo "Testing GPU access in Docker container..."
echo "=========================================="

# Test 1: Basic GPU visibility
echo -e "\n1. Testing NVIDIA GPU visibility:"
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi

if [ $? -eq 0 ]; then
    echo "✓ GPU is accessible in Docker"
else
    echo "✗ GPU not accessible. Please check NVIDIA Container Toolkit installation"
    echo "  Install with: sudo apt-get install nvidia-container-toolkit"
    echo "  Then restart Docker: sudo systemctl restart docker"
    exit 1
fi

# Test 2: Test with our container (if built)
if docker images | grep -q "motion-video-api"; then
    echo -e "\n2. Testing GPU in MOTION container:"
    docker run --rm --gpus all motion-video-api:latest python3 -c "
import torch
print('PyTorch version:', torch.__version__)
print('CUDA available:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('CUDA device count:', torch.cuda.device_count())
    print('CUDA device name:', torch.cuda.get_device_name(0))
    print('CUDA memory (GB):', torch.cuda.get_device_properties(0).total_memory / 1024**3)
"
else
    echo -e "\n2. MOTION container not built yet. Build with:"
    echo "   docker build -t motion-video-api:latest ."
fi

echo -e "\nGPU test complete!"