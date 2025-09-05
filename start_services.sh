#!/bin/bash

echo "Starting MOTION Video Generation Services"
echo "========================================"

# Check if ComfyUI is installed
if [ ! -d "ComfyUI" ]; then
    echo "Error: ComfyUI directory not found!"
    echo "Please run setup_models.sh first"
    exit 1
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

# Install Python dependencies if needed
echo "Checking Python dependencies..."

if ! python3 -c "import torch" 2>/dev/null; then
    echo "Installing PyTorch..."
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
fi

if [ ! -f ".deps_installed" ]; then
    echo "Installing ComfyUI dependencies..."
    pip3 install -r ComfyUI/requirements.txt
    
    echo "Installing API dependencies..."
    pip3 install -r requirements-api.txt
    
    touch .deps_installed
fi

# Start ComfyUI in background
echo "Starting ComfyUI server on port 9188..."
cd ComfyUI
python3 main.py --listen 0.0.0.0 --port 9188 > ../comfyui.log 2>&1 &
COMFYUI_PID=$!
cd ..

echo "Waiting for ComfyUI to initialize..."
sleep 10

# Check if ComfyUI is running
if ! ps -p $COMFYUI_PID > /dev/null; then
    echo "Error: ComfyUI failed to start. Check comfyui.log for details"
    exit 1
fi

# Start API service
echo "Starting API service on port 9000..."
COMFYUI_PORT=9188 API_PORT=9000 python3 api_service.py > api_service.log 2>&1 &
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