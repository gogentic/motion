FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_MODULE_LOADING=LAZY
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3-pip \
    git \
    wget \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgoogle-perftools4 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.11 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

WORKDIR /app

# Install PyTorch with CUDA support first
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# Copy ComfyUI
COPY ComfyUI /app/ComfyUI

# Install ComfyUI requirements
WORKDIR /app/ComfyUI
RUN pip3 install --no-cache-dir -r requirements.txt

# Install additional Python packages for video processing
RUN pip3 install --no-cache-dir \
    opencv-python \
    imageio \
    imageio-ffmpeg \
    moviepy \
    transformers \
    accelerate \
    xformers

# Clone and install required custom nodes
WORKDIR /app/ComfyUI/custom_nodes

# AnimateDiff for video generation
RUN git clone https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved.git && \
    cd ComfyUI-AnimateDiff-Evolved && \
    pip3 install -r requirements.txt || true

# Video Helper Suite for video export
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && \
    cd ComfyUI-VideoHelperSuite && \
    pip3 install -r requirements.txt || true

# ComfyUI Manager for easier management
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    pip3 install -r requirements.txt || true

# Frame Interpolation for smoother videos (optional)
RUN git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && \
    cd ComfyUI-Frame-Interpolation && \
    python3 install.py || true

WORKDIR /app

# Copy API service and requirements
COPY api_service.py /app/
COPY requirements-api.txt /app/
COPY workflows /app/workflows

# Install API requirements
RUN pip3 install --no-cache-dir -r requirements-api.txt

# Create necessary directories
RUN mkdir -p \
    /app/ComfyUI/models/checkpoints \
    /app/ComfyUI/models/vae \
    /app/ComfyUI/models/loras \
    /app/ComfyUI/models/embeddings \
    /app/ComfyUI/models/controlnet \
    /app/ComfyUI/models/animatediff_models \
    /app/ComfyUI/models/animatediff_motion_lora \
    /app/output \
    /app/ComfyUI/input \
    /app/ComfyUI/output \
    /app/ComfyUI/temp

# Copy entrypoint script
COPY docker-entrypoint.sh /app/
RUN chmod +x /app/docker-entrypoint.sh

# Expose ports
EXPOSE 9188 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

ENTRYPOINT ["/app/docker-entrypoint.sh"]