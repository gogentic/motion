# MOTION Project - Claude Documentation

## Project Overview
MOTION is a headless ComfyUI service that generates B-roll video clips from text scripts. It processes scripts and generates 2 video clips (5-8 seconds each) per minute of script content.

## Current State (As of Sep 4, 2025)

### ✅ Completed Setup
1. **Docker Container Built** (25.9GB)
   - Base image: `motion-video-api:latest`
   - Simple WebUI image: `comfyui-webui:latest`
   - All dependencies included (PyTorch, CUDA, custom nodes)
   - GPU access verified (RTX 4090)

2. **Web Access Configured**
   - URL: https://motion.gognetic.ai
   - Nginx reverse proxy configured
   - SSL/HTTPS enabled via Let's Encrypt
   - Port 9188 closed for security (nginx handles all traffic)

3. **Current Running Mode**
   - Container: `simple-comfyui-host` (WebUI mode for model installation)
   - Running on host network, port 9188
   - Accessible via https://motion.gognetic.ai

## Architecture

### Two Separate ComfyUI Instances
1. **Existing WebUI** (comfy.gognetic.ai) - Team's creative work on port 8188
2. **MOTION Service** (motion.gognetic.ai) - Dedicated headless B-roll generation on port 9188

Both services share the RTX 4090 GPU via Docker's nvidia-container-runtime without conflicts.

## Service Modes

### 1. WebUI Mode (Currently Active)
For model installation and workflow testing:
```bash
# Start WebUI
docker run --rm -d --gpus all --network host \
  -v $(pwd)/models:/app/ComfyUI/models \
  -v $(pwd)/output:/app/ComfyUI/output \
  --name simple-comfyui-host \
  comfyui-webui:latest \
  python3 /app/ComfyUI/main.py --listen 0.0.0.0 --port 9188
```

### 2. API Mode (Production)
For automated script-to-video generation:
```bash
# Stop WebUI
docker stop simple-comfyui-host

# Start API service
docker compose -p motion -f docker-compose.prod.yml up -d
```

## API Service Details

### Endpoints (When in API Mode)
- `POST /generate` - Submit script for video generation
- `GET /status/{job_id}` - Check job status
- `GET /download/{job_id}/{filename}` - Download generated videos
- `GET /health` - Service health check

### Example API Usage
```python
import requests

# Submit script
response = requests.post('http://localhost:9000/generate', json={
    'script': 'A peaceful sunset over the ocean...',
    'clips_per_minute': 2,
    'clip_duration': 6.5,
    'style': 'cinematic',
    'resolution': '512x512',
    'fps': 8
})
job_id = response.json()['job_id']

# Check status
status = requests.get(f'http://localhost:9000/status/{job_id}').json()
```

## Model Requirements

### Minimum Required Models
1. **Stable Diffusion Checkpoint** 
   - Location: `models/checkpoints/`
   - Recommended: SD 1.5 for faster generation
   - Alternative: SDXL for higher quality

2. **AnimateDiff Motion Module**
   - Location: `models/animatediff_models/`
   - Required: `mm_sd_v15_v2.ckpt`

3. **VAE (Optional but recommended)**
   - Location: `models/vae/`

### Model Installation
Use ComfyUI Manager in WebUI mode (https://motion.gognetic.ai) to:
- Download models from CivitAI
- Install additional custom nodes
- Download LoRAs for style control

## Switching to Production API Mode

### Step 1: Ensure Models Are Installed
Verify models exist in:
- `./models/checkpoints/` - At least one SD model
- `./models/animatediff_models/` - Motion module

### Step 2: Stop WebUI and Start API
```bash
# Stop WebUI container
docker stop simple-comfyui-host

# Start production API
docker compose -p motion -f docker-compose.prod.yml up -d

# Check logs
docker compose -p motion -f docker-compose.prod.yml logs -f
```

### Step 3: Configure Nginx for API (Optional)
If you want API access via HTTPS:
1. Run: `sudo ./setup_nginx.sh`
2. Choose option 2 for API setup
3. This will create: https://motion-api.gognetic.ai

### Step 4: Test the API
```bash
# Local test
python3 examples/test_api.py

# Or direct curl
curl -X POST http://localhost:9000/generate \
  -H "Content-Type: application/json" \
  -d '{"script": "Test scene description"}'
```

## Important Files

### Configuration Files
- `docker-compose.prod.yml` - Production API service
- `docker-compose.webui.yml` - WebUI service
- `api_service.py` - FastAPI application
- `workflows/video_generation.json` - ComfyUI workflow

### Scripts
- `setup_production.sh` - Initial setup and model download
- `launch_webui.sh` - Start WebUI mode
- `start.sh` - Start production API
- `stop.sh` - Stop services
- `test_gpu.sh` - Verify GPU access

### Dockerfiles
- `Dockerfile` - Main production image (complex, has issues)
- `Dockerfile.webui` - Simplified WebUI image (currently using)

## Troubleshooting

### If API fails to start
1. Check models are installed: `ls -la models/checkpoints/`
2. Verify GPU access: `./test_gpu.sh`
3. Check logs: `docker compose -p motion -f docker-compose.prod.yml logs`

### If videos aren't generating
1. Reduce resolution to 512x512
2. Lower clip_duration to 3-4 seconds
3. Check VRAM usage: `nvidia-smi`

### Port conflicts
- Existing ComfyUI uses port 8188
- MOTION WebUI uses port 9188  
- MOTION API uses port 9000

## Network Details
- Server internal IP: 10.0.0.81
- Public IP: 73.242.252.148
- IPv6: 2601:8c3:8578:4bd0::1234
- Behind NAT, using nginx for public access

## Security Notes
- Port 9188 is now closed (nginx proxies traffic)
- HTTPS enabled with Let's Encrypt
- Services run in Docker containers for isolation
- GPU sharing handled by nvidia-container-runtime

## Next Steps for Production
1. ✅ Install models via WebUI
2. ⏳ Test workflow with sample scripts
3. ⏳ Switch to API mode
4. ⏳ Integrate with your application
5. ⏳ Set up monitoring and logging
6. ⏳ Configure backup strategy for models

## Quick Commands Reference
```bash
# Check what's running
docker ps | grep -E "comfyui|motion"

# View logs
docker logs simple-comfyui-host --tail 50

# Restart WebUI
docker restart simple-comfyui-host

# Switch to API mode
docker stop simple-comfyui-host && \
docker compose -p motion -f docker-compose.prod.yml up -d

# Switch back to WebUI
docker compose -p motion -f docker-compose.prod.yml down && \
./launch_webui.sh
```