#!/bin/bash

echo "Launching MOTION ComfyUI with Web Interface"
echo "==========================================="
echo ""
echo "This will start ComfyUI with the web interface for model management."
echo "Access it at: http://localhost:9188"
echo ""

# Stop any running production service first
if docker ps | grep -q motion-video-api; then
    echo "Stopping production service..."
    docker-compose -f docker-compose.prod.yml down
fi

# Run container with web UI accessible
docker run --rm -d \
    --gpus all \
    -p 9188:9188 \
    -v $(pwd)/models:/app/ComfyUI/models \
    -v $(pwd)/custom_nodes:/app/ComfyUI/custom_nodes \
    -v $(pwd)/output:/app/output \
    -v $(pwd)/input:/app/ComfyUI/input \
    -v $(pwd)/workflows:/app/workflows \
    --name motion-webui \
    motion-video-api:latest \
    bash -c "cd /app/ComfyUI && python3 main.py --listen 0.0.0.0 --port 9188"

echo "✓ ComfyUI WebUI started!"
echo ""
echo "Access at: http://localhost:9188"
echo ""
echo "To view logs:    docker logs -f motion-webui"
echo "To stop:         docker stop motion-webui"

echo ""
echo "ComfyUI stopped. You can now restart the production service with:"
echo "  ./start.sh"