# MOTION - Script to Video Generation Service

A headless ComfyUI-based service that generates video clips from text scripts using AI. The service processes scripts and generates 2 video clips (5-8 seconds each) per minute of script content.

## Features

- **RESTful API** for script submission and job management
- **Automatic scene parsing** from scripts
- **Video generation** using Stable Diffusion + AnimateDiff
- **Dockerized deployment** with GPU support
- **Async processing** with job tracking
- **Customizable parameters** (style, resolution, FPS, duration)

## System Requirements

- Ubuntu Server with NVIDIA GPU (tested on RTX 4090)
- Docker and Docker Compose
- NVIDIA Container Toolkit
- At least 16GB VRAM recommended
- 50GB+ free disk space for models

## Installation

### 1. Clone and Setup

```bash
# Make setup script executable
chmod +x setup_models.sh

# Run setup to create directories and install custom nodes
./setup_models.sh
```

### 2. Download Required Models

The service requires AI models to generate videos. You have two options:

#### Option A: Automatic Download (Recommended)
```bash
pip install tqdm requests
python download_models.py --model all
```

#### Option B: Manual Download
Download these models and place them in the specified directories:

1. **Stable Diffusion Model** (2.5GB)
   - [SD 1.5](https://huggingface.co/runwayml/stable-diffusion-v1-5/blob/main/v1-5-pruned-emaonly.safetensors)
   - Place in: `ComfyUI/models/checkpoints/`

2. **AnimateDiff Motion Module** (1.7GB)
   - [mm_sd_v15_v2.ckpt](https://huggingface.co/guoyww/animatediff/blob/main/mm_sd_v15_v2.ckpt)
   - Place in: `ComfyUI/models/animatediff_models/`

3. **VAE** (Optional, 335MB)
   - [vae-ft-mse](https://huggingface.co/stabilityai/sd-vae-ft-mse-original/blob/main/vae-ft-mse-840000-ema-pruned.safetensors)
   - Place in: `ComfyUI/models/vae/`

### 3. Build and Run with Docker

```bash
# Build and start the service
docker-compose up --build

# Run in background
docker-compose up -d
```

## API Usage

### Submit a Script for Video Generation

```bash
curl -X POST http://localhost:9000/generate \
  -H "Content-Type: application/json" \
  -d '{
    "script": "A serene mountain landscape at dawn. The sun slowly rises behind snow-capped peaks. Eagles soar through the morning mist. A river flows through the valley below.",
    "clips_per_minute": 2,
    "clip_duration": 6.5,
    "style": "cinematic",
    "resolution": "512x512",
    "fps": 8
  }'
```

### Check Job Status

```bash
curl http://localhost:9000/status/{job_id}
```

### Download Generated Videos

```bash
curl -O http://localhost:9000/download/{job_id}/{filename}
```

### Health Check

```bash
curl http://localhost:9000/health
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Service info and available endpoints |
| `/generate` | POST | Submit script for video generation |
| `/status/{job_id}` | GET | Check job status and progress |
| `/download/{job_id}/{filename}` | GET | Download generated video file |
| `/health` | GET | Service health check |

## Request Parameters

### POST /generate

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `script` | string | required | The text script to convert to video |
| `clips_per_minute` | int | 2 | Number of clips per script minute |
| `clip_duration` | float | 6.5 | Duration of each clip in seconds |
| `style` | string | "cinematic" | Visual style for generation |
| `resolution` | string | "512x512" | Video resolution (WxH) |
| `fps` | int | 8 | Frames per second |

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Client    │────▶│  API Service │────▶│  ComfyUI    │
│  (Script)   │◀────│   (FastAPI)  │◀────│  (Headless) │
└─────────────┘     └──────────────┘     └─────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │   Job Queue  │
                    │  (Async BG)  │
                    └──────────────┘
```

## Performance

- **Processing Time**: ~30-60 seconds per clip (depends on GPU and settings)
- **VRAM Usage**: 8-12GB during generation
- **Output Format**: WebP animated images or MP4 videos
- **Recommended Settings**: 
  - Resolution: 512x512 for faster generation
  - FPS: 8 for smooth motion with reasonable generation time
  - Steps: 20 for balanced quality/speed

## Customization

### Modify Video Workflow

Edit `workflows/video_generation.json` to customize the ComfyUI workflow.

### Add Custom Nodes

Place additional ComfyUI custom nodes in `ComfyUI/custom_nodes/`

### Change Models

Update model references in `api_service.py` to use different checkpoints.

## Troubleshooting

### GPU Not Detected
```bash
# Check NVIDIA driver
nvidia-smi

# Verify Docker GPU support
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

### Out of Memory
- Reduce resolution to 512x512 or lower
- Decrease batch_size/clip_duration
- Use SD 1.5 models instead of SDXL

### Slow Generation
- Reduce sampling steps (minimum 15)
- Use simpler schedulers (euler, ddim)
- Lower resolution

## Development

### Run Without Docker

```bash
# Terminal 1: Start ComfyUI
cd ComfyUI
python main.py --listen 0.0.0.0

# Terminal 2: Start API Service
pip install -r requirements-api.txt
python api_service.py
```

### API Testing

See `examples/test_api.py` for example client code.

## License

This project uses ComfyUI and various AI models. Please respect their individual licenses.

## Support

For issues and questions, please check:
1. ComfyUI documentation
2. Docker logs: `docker-compose logs -f`
3. API health endpoint: `http://localhost:9000/health`