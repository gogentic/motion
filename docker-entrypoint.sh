#!/bin/bash
set -e

echo "Starting ComfyUI server..."
cd /app/ComfyUI
python3 main.py --listen 0.0.0.0 --port 9188 &
COMFYUI_PID=$!

echo "Waiting for ComfyUI to be ready..."
sleep 10

echo "Starting API service..."
cd /app
COMFYUI_PORT=9188 API_PORT=9000 python3 api_service.py &
API_PID=$!

echo "Services started:"
echo "  - ComfyUI: http://0.0.0.0:9188"
echo "  - API Service: http://0.0.0.0:9000"

wait $COMFYUI_PID $API_PID