#!/bin/bash

echo "MOTION Production Setup"
echo "======================="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo "Please don't run this script as root"
   exit 1
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    echo "   Install with: sudo apt-get install docker.io docker-compose"
    exit 1
else
    echo "✅ Docker found"
fi

# Check NVIDIA Docker support
if ! docker run --rm --gpus all nvidia/cuda:12.1.0-base nvidia-smi &> /dev/null; then
    echo "❌ NVIDIA Container Toolkit not working"
    echo "   Install with:"
    echo "   curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -"
    echo "   distribution=$(. /etc/os-release;echo \$ID\$VERSION_ID)"
    echo "   curl -s -L https://nvidia.github.io/nvidia-docker/\$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list"
    echo "   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit"
    echo "   sudo systemctl restart docker"
    exit 1
else
    echo "✅ GPU support working"
fi

# Create directories
echo ""
echo "Creating directories..."
mkdir -p models/checkpoints models/animatediff_models models/vae models/loras
mkdir -p output input workflows logs
echo "✅ Directories created"

# Check for models
echo ""
echo "Checking for models..."
MODEL_COUNT=$(find models -name "*.safetensors" -o -name "*.ckpt" 2>/dev/null | wc -l)

if [ "$MODEL_COUNT" -eq 0 ]; then
    echo "⚠️  No models found. Would you like to download starter models? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Downloading SD 1.5 model (1.7GB)..."
        wget -c -O models/checkpoints/v1-5-pruned-emaonly.safetensors \
            https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors
        
        echo "Downloading AnimateDiff model (1.7GB)..."
        wget -c -O models/animatediff_models/mm_sd_v15_v2.ckpt \
            https://huggingface.co/guoyww/animatediff/resolve/main/mm_sd_v15_v2.ckpt
        
        echo "✅ Models downloaded"
    else
        echo "⚠️  Remember to add models before running"
    fi
else
    echo "✅ Found $MODEL_COUNT model files"
fi

# Build Docker image if needed
echo ""
if ! docker images | grep -q "motion-video-api"; then
    echo "Building Docker image (this may take 10-15 minutes)..."
    docker build -t motion-video-api:latest .
    echo "✅ Docker image built"
else
    echo "✅ Docker image already built"
fi

# Create systemd service (optional)
echo ""
echo "Would you like to install as a systemd service for auto-start? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    cat > motion-api.service << EOF
[Unit]
Description=MOTION Video Generation API
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=10
User=$USER
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/docker-compose -f docker-compose.prod.yml up
ExecStop=/usr/bin/docker-compose -f docker-compose.prod.yml down

[Install]
WantedBy=multi-user.target
EOF
    
    echo "Service file created. To install:"
    echo "  sudo cp motion-api.service /etc/systemd/system/"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable motion-api"
    echo "  sudo systemctl start motion-api"
fi

# Create convenience scripts
echo ""
echo "Creating convenience scripts..."

cat > start.sh << 'EOF'
#!/bin/bash
docker-compose -f docker-compose.prod.yml up -d
echo "MOTION API started at http://localhost:9000"
echo "View logs with: docker-compose -f docker-compose.prod.yml logs -f"
EOF
chmod +x start.sh

cat > stop.sh << 'EOF'
#!/bin/bash
docker-compose -f docker-compose.prod.yml down
echo "MOTION API stopped"
EOF
chmod +x stop.sh

cat > logs.sh << 'EOF'
#!/bin/bash
docker-compose -f docker-compose.prod.yml logs -f
EOF
chmod +x logs.sh

echo "✅ Convenience scripts created: start.sh, stop.sh, logs.sh"

# Final summary
echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Quick Start:"
echo "  ./start.sh         - Start the service"
echo "  ./stop.sh          - Stop the service"
echo "  ./logs.sh          - View logs"
echo ""
echo "API Endpoints:"
echo "  http://localhost:9000         - API root"
echo "  http://localhost:9000/health  - Health check"
echo ""
echo "Test with:"
echo "  python3 examples/test_api.py"
echo ""
echo "Models directory: $(pwd)/models"
echo "Output directory: $(pwd)/output"
echo ""

# Check if service should start now
echo "Would you like to start the service now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    ./start.sh
fi