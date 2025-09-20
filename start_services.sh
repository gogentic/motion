#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"
COMFY_DIR="$ROOT_DIR/ComfyUI"
PYTHON_BIN="$COMFY_DIR/venv/bin/python"

# Ensure uv cache is writable (ComfyUI-Manager prestart)
export UV_CACHE_DIR="$ROOT_DIR/.uv-cache"
mkdir -p "$UV_CACHE_DIR"
chmod 700 "$UV_CACHE_DIR"

echo "Starting MOTION Video Generation Services"
echo "========================================"

# Check if ComfyUI is installed
if [ ! -d "$COMFY_DIR" ]; then
    echo "Error: ComfyUI directory not found!"
    echo "Please run setup_models.sh first"
    exit 1
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

# Install Python dependencies via helper script
echo "Preparing Python environment..."
if ! ./scripts/prepare_comfy_env.sh; then
    echo "Failed to prepare the ComfyUI environment. Fix the issues above and retry."
    exit 1
fi

# Double-check torch is available (prepare script should have installed it via requirements, but install explicitly if missing)
if ! "$PYTHON_BIN" -c "import torch" >/dev/null 2>&1; then
    echo "PyTorch not detected in the virtual environment. Installing CUDA 12.1 wheels..."
    "$PYTHON_BIN" -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
fi

# Start ComfyUI in background
echo "Starting ComfyUI server on port 9188..."
# Verify GPU availability before launching ComfyUI
if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "Error: nvidia-smi not found. GPU runtime not available."
    exit 1
fi

if ! nvidia-smi >/dev/null 2>&1; then
    echo "Error: GPU driver not ready (nvidia-smi failed). Resolve CUDA driver issues before starting."
    exit 1
fi

export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"

cd "$COMFY_DIR"
"$PYTHON_BIN" main.py --listen 0.0.0.0 --port 9188 --output-directory "$ROOT_DIR/output" --input-directory "$ROOT_DIR/input" > "$ROOT_DIR/comfyui.log" 2>&1 &
COMFYUI_PID=$!
cd "$ROOT_DIR"

echo "Waiting for ComfyUI to initialize..."
COMFY_READY=0
for i in $(seq 1 30); do
    if ! ps -p $COMFYUI_PID > /dev/null; then
        echo "Error: ComfyUI failed to start. Check comfyui.log for details"
        exit 1
    fi

    if curl -sf "http://127.0.0.1:9188" >/dev/null 2>&1; then
        COMFY_READY=1
        break
    fi

    sleep 2
done

if [ "$COMFY_READY" -ne 1 ]; then
    echo "Error: ComfyUI failed to become ready within timeout."
    kill $COMFYUI_PID >/dev/null 2>&1 || true
    exit 1
fi

# Start API service
echo "Starting API service on port 9000..."
COMFYUI_PORT=9188 API_PORT=9000 "$PYTHON_BIN" api_service.py > api_service.log 2>&1 &
API_PID=$!

sleep 3

# Check if API is running
if ! ps -p $API_PID > /dev/null; then
    echo "Error: API service failed to start. Check api_service.log for details"
    kill $COMFYUI_PID
    exit 1
fi

echo ""
echo "Services started successfully!"
echo "=============================="
echo "ComfyUI PID: $COMFYUI_PID (http://localhost:9188)"
echo "API Service PID: $API_PID (http://localhost:9000)"
echo ""
echo "Logs:"
echo "  - ComfyUI: comfyui.log"
echo "  - API: api_service.log"
echo ""
echo "To stop services, run: kill $COMFYUI_PID $API_PID"
echo ""
echo "To test the API:"
echo "  python3 examples/test_api.py"
echo ""

# Save PIDs to file for easy stopping
echo "COMFYUI_PID=$COMFYUI_PID" > .pids
echo "API_PID=$API_PID" >> .pids

# Keep script running and forward signals
trap "echo 'Stopping services...'; kill $COMFYUI_PID $API_PID; exit" SIGINT SIGTERM

echo "Press Ctrl+C to stop all services"
wait
