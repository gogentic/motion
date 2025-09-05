# MOTION Deployment Guide

## Architecture Overview

Your setup will have **two separate ComfyUI instances**:
1. **WebUI ComfyUI** (existing at comfy.gognetic.ai) - For team's creative work
2. **Headless ComfyUI** (this MOTION service) - Dedicated B-roll video generation

Both can share the same GPU (RTX 4090) as Docker's nvidia-container-runtime handles GPU virtualization.

## Quick Start

### 1. Download Required Models

First, download the minimal models needed for video generation:

```bash
# Create model directories
mkdir -p models/checkpoints models/animatediff_models models/vae

# Download SD 1.5 (faster than SDXL for B-roll)
wget -O models/checkpoints/v1-5-pruned-emaonly.safetensors \
  https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors

# Download AnimateDiff motion model
wget -O models/animatediff_models/mm_sd_v15_v2.ckpt \
  https://huggingface.co/guoyww/animatediff/resolve/main/mm_sd_v15_v2.ckpt
```

### 2. Start with Docker Compose

```bash
# Production deployment
docker-compose -f docker-compose.prod.yml up -d

# Check logs
docker-compose -f docker-compose.prod.yml logs -f

# Stop service
docker-compose -f docker-compose.prod.yml down
```

### 3. Test the API

```bash
# Health check
curl http://localhost:9000/health

# Submit a test script
curl -X POST http://localhost:9000/generate \
  -H "Content-Type: application/json" \
  -d '{
    "script": "A peaceful sunset over the ocean. Waves gently crash on the shore.",
    "clips_per_minute": 2,
    "clip_duration": 5
  }'
```

## GPU Resource Management

### Option 1: Shared GPU (Recommended)
Both services can share the RTX 4090. Docker handles this automatically.

```yaml
# In docker-compose.prod.yml
environment:
  - CUDA_VISIBLE_DEVICES=0  # Both services use GPU 0
```

### Option 2: GPU Memory Limits
If you experience OOM issues, limit VRAM usage:

```yaml
environment:
  - PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512
  - COMFYUI_VRAM_LIMIT=8000  # Limit to 8GB VRAM
```

### Option 3: Time-based Scheduling
Use systemd timers or cron to run services at different times:

```bash
# Run B-roll generation at night
0 2 * * * docker-compose -f docker-compose.prod.yml up
```

## Production Considerations

### 1. Model Storage
- Keep models on fast NVMe SSD
- Consider symlinks to share common models between instances
- Each checkpoint is ~2-5GB

### 2. Output Management
- Videos are saved to `./output` directory
- Implement cleanup policy (delete after 7 days)
- Consider S3/object storage for long-term storage

### 3. Monitoring
```bash
# GPU usage
nvidia-smi -l 1

# Container resources
docker stats motion-video-api

# Service health
watch -n 5 'curl -s http://localhost:9000/health | jq'
```

### 4. Scaling Options

#### Vertical Scaling
- Increase batch size in workflows
- Process multiple clips in parallel

#### Horizontal Scaling
- Run multiple container instances on different GPUs
- Use a queue (Redis/RabbitMQ) for job distribution

## Troubleshooting

### GPU Not Available
```bash
# Check NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.1.0-base nvidia-smi

# Restart Docker daemon
sudo systemctl restart docker
```

### Out of Memory
- Reduce resolution to 512x512
- Lower batch_size in workflow
- Restart container to clear VRAM

### Slow Generation
- Use SD 1.5 instead of SDXL
- Reduce sampling steps to 15
- Disable unnecessary custom nodes

## API Integration Examples

### Python Client
```python
import requests
import time

# Submit job
response = requests.post('http://localhost:9000/generate', json={
    'script': 'Your script here',
    'clips_per_minute': 2
})
job_id = response.json()['job_id']

# Poll status
while True:
    status = requests.get(f'http://localhost:9000/status/{job_id}').json()
    if status['status'] in ['completed', 'failed']:
        break
    time.sleep(5)
```

### Node.js Client
```javascript
const axios = require('axios');

async function generateVideo(script) {
    const { data } = await axios.post('http://localhost:9000/generate', {
        script,
        clips_per_minute: 2
    });
    return data.job_id;
}
```

## Security

### Network Isolation
```yaml
# Create isolated network
networks:
  motion-network:
    driver: bridge
    internal: true  # No external access
```

### API Authentication (TODO)
Add authentication to the API service:
- JWT tokens
- API keys
- Rate limiting

## Backup & Recovery

### Backup Models
```bash
# Backup models to external storage
rsync -av ./models/ /backup/motion-models/
```

### Backup Configurations
```bash
# Backup workflows and configs
tar -czf motion-backup-$(date +%Y%m%d).tar.gz workflows/ docker-compose.prod.yml
```

## Next Steps

1. **Set up monitoring** - Prometheus + Grafana for metrics
2. **Add queue system** - Redis for job queue management
3. **Implement caching** - Cache generated clips for reuse
4. **Add watermarking** - Brand your B-roll videos
5. **Webhook notifications** - Notify when videos are ready