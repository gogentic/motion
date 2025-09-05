import asyncio
import json
import uuid
import os
import time
from pathlib import Path
from typing import Optional, List, Dict, Any
from dataclasses import dataclass
from enum import Enum

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse, FileResponse
from pydantic import BaseModel
import aiohttp
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Motion Video Generation API", version="1.0.0")

COMFYUI_HOST = os.getenv("COMFYUI_HOST", "localhost")
COMFYUI_PORT = os.getenv("COMFYUI_PORT", "9188")
COMFYUI_URL = f"http://{COMFYUI_HOST}:{COMFYUI_PORT}"
API_PORT = int(os.getenv("API_PORT", "9000"))

OUTPUT_DIR = Path("./output")
OUTPUT_DIR.mkdir(exist_ok=True)

class JobStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class ScriptRequest(BaseModel):
    script: str
    clips_per_minute: int = 2
    clip_duration: float = 6.5  # 5-8 seconds average
    style: Optional[str] = "cinematic"
    resolution: Optional[str] = "1920x1080"
    fps: Optional[int] = 30
    workflow: Optional[Dict] = None  # Custom workflow override

class JobResponse(BaseModel):
    job_id: str
    status: JobStatus
    message: str

class JobStatusResponse(BaseModel):
    job_id: str
    status: JobStatus
    progress: Optional[float] = None
    clips_generated: Optional[int] = None
    total_clips: Optional[int] = None
    output_files: Optional[List[str]] = None
    error: Optional[str] = None

@dataclass
class VideoJob:
    job_id: str
    script: str
    clips_per_minute: int
    clip_duration: float
    style: str
    resolution: str
    fps: int
    status: JobStatus
    workflow: Optional[Dict] = None
    progress: float = 0.0
    clips_generated: int = 0
    total_clips: int = 0
    output_files: List[str] = None
    error: Optional[str] = None

    def __post_init__(self):
        if self.output_files is None:
            self.output_files = []

jobs_db: Dict[str, VideoJob] = {}

def parse_script_to_scenes(script: str, clips_per_minute: int) -> List[Dict[str, Any]]:
    lines = script.strip().split('\n')
    non_empty_lines = [line.strip() for line in lines if line.strip()]
    
    words_per_minute = 150
    total_words = sum(len(line.split()) for line in non_empty_lines)
    duration_minutes = total_words / words_per_minute
    
    total_clips = int(duration_minutes * clips_per_minute)
    if total_clips < 1:
        total_clips = 1
    
    scenes = []
    lines_per_clip = max(1, len(non_empty_lines) // total_clips)
    
    for i in range(0, len(non_empty_lines), lines_per_clip):
        scene_text = ' '.join(non_empty_lines[i:i+lines_per_clip])
        scenes.append({
            'text': scene_text,
            'index': len(scenes),
            'total': total_clips
        })
    
    return scenes[:total_clips]

def create_video_workflow(scene: Dict[str, Any], style: str, resolution: str, fps: int, duration: float) -> Dict:
    width, height = map(int, resolution.split('x'))
    total_frames = int(fps * duration)
    
    workflow = {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {
                "ckpt_name": "sd_xl_base_1.0.safetensors"
            }
        },
        "2": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": f"{style} video scene: {scene['text']}",
                "clip": ["1", 1]
            }
        },
        "3": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": "blurry, low quality, distorted, ugly",
                "clip": ["1", 1]
            }
        },
        "4": {
            "class_type": "EmptyLatentImage",
            "inputs": {
                "width": width,
                "height": height,
                "batch_size": total_frames
            }
        },
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": scene['index'] * 1000,
                "steps": 20,
                "cfg": 7.0,
                "sampler_name": "euler",
                "scheduler": "normal",
                "denoise": 1.0,
                "model": ["1", 0],
                "positive": ["2", 0],
                "negative": ["3", 0],
                "latent_image": ["4", 0]
            }
        },
        "6": {
            "class_type": "VAEDecode",
            "inputs": {
                "samples": ["5", 0],
                "vae": ["1", 2]
            }
        },
        "7": {
            "class_type": "SaveAnimatedWEBP",
            "inputs": {
                "filename_prefix": f"motion_scene_{scene['index']:03d}",
                "fps": fps,
                "lossless": False,
                "quality": 80,
                "method": "default",
                "images": ["6", 0]
            }
        }
    }
    
    return workflow

async def execute_workflow(workflow: Dict, job_id: str) -> Dict:
    try:
        prompt_id = str(uuid.uuid4())
        
        payload = {
            "prompt": workflow,
            "client_id": job_id
        }
        
        async with aiohttp.ClientSession() as session:
            async with session.post(f"{COMFYUI_URL}/prompt", json=payload) as resp:
                if resp.status != 200:
                    text = await resp.text()
                    raise Exception(f"Failed to queue prompt: {text}")
                
                result = await resp.json()
                prompt_id = result.get('prompt_id')
        
        max_wait = 600  # 10 minutes for large models like Hunyuan
        start_time = time.time()
        
        while time.time() - start_time < max_wait:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{COMFYUI_URL}/history/{prompt_id}") as resp:
                    if resp.status == 200:
                        history = await resp.json()
                        if prompt_id in history:
                            return history[prompt_id]
            
            await asyncio.sleep(2)
        
        raise TimeoutError(f"Workflow execution timed out after {max_wait} seconds")
        
    except Exception as e:
        logger.error(f"Workflow execution error: {str(e)}")
        raise

async def process_video_job(job: VideoJob):
    try:
        job.status = JobStatus.PROCESSING
        
        # If custom workflow provided, use it directly
        if job.workflow:
            job.total_clips = 1
            result = await execute_workflow(job.workflow, job.job_id)
            
            if result.get('outputs'):
                for output in result['outputs'].values():
                    if 'images' in output:
                        for image in output['images']:
                            output_path = f"output/{image['filename']}"
                            job.output_files.append(output_path)
            
            job.clips_generated = 1
            job.progress = 100.0
        else:
            # Use default workflow generation
            scenes = parse_script_to_scenes(job.script, job.clips_per_minute)
            job.total_clips = len(scenes)
            
            for i, scene in enumerate(scenes):
                workflow = create_video_workflow(
                    scene=scene,
                    style=job.style,
                    resolution=job.resolution,
                    fps=job.fps,
                    duration=job.clip_duration
                )
                
                result = await execute_workflow(workflow, job.job_id)
                
                if result.get('outputs'):
                    for output in result['outputs'].values():
                        if 'images' in output:
                            for image in output['images']:
                                output_path = f"output/{image['filename']}"
                                job.output_files.append(output_path)
                
                job.clips_generated = i + 1
                job.progress = (i + 1) / len(scenes) * 100
                
                logger.info(f"Job {job.job_id}: Completed clip {i+1}/{len(scenes)}")
        
        job.status = JobStatus.COMPLETED
        job.progress = 100.0
        
    except Exception as e:
        logger.error(f"Job {job.job_id} failed: {str(e)}")
        job.status = JobStatus.FAILED
        job.error = str(e)

@app.post("/generate", response_model=JobResponse)
async def generate_video(request: ScriptRequest, background_tasks: BackgroundTasks):
    job_id = str(uuid.uuid4())
    
    job = VideoJob(
        job_id=job_id,
        script=request.script,
        clips_per_minute=request.clips_per_minute,
        clip_duration=request.clip_duration,
        style=request.style,
        resolution=request.resolution,
        fps=request.fps,
        workflow=request.workflow,
        status=JobStatus.PENDING
    )
    
    jobs_db[job_id] = job
    
    background_tasks.add_task(process_video_job, job)
    
    return JobResponse(
        job_id=job_id,
        status=JobStatus.PENDING,
        message=f"Job queued. Will generate {request.clips_per_minute} clips per minute of script."
    )

@app.get("/status/{job_id}", response_model=JobStatusResponse)
async def get_job_status(job_id: str):
    if job_id not in jobs_db:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs_db[job_id]
    
    return JobStatusResponse(
        job_id=job.job_id,
        status=job.status,
        progress=job.progress,
        clips_generated=job.clips_generated,
        total_clips=job.total_clips,
        output_files=job.output_files,
        error=job.error
    )

@app.get("/download/{job_id}/{filename}")
async def download_output(job_id: str, filename: str):
    if job_id not in jobs_db:
        raise HTTPException(status_code=404, detail="Job not found")
    
    file_path = OUTPUT_DIR / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(file_path)

@app.get("/health")
async def health_check():
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{COMFYUI_URL}/system_stats") as resp:
                comfyui_healthy = resp.status == 200
    except:
        comfyui_healthy = False
    
    return {
        "status": "healthy" if comfyui_healthy else "degraded",
        "comfyui": "connected" if comfyui_healthy else "disconnected"
    }

@app.get("/")
async def root():
    return {
        "service": "Motion Video Generation API",
        "version": "1.0.0",
        "endpoints": {
            "POST /generate": "Submit a script for video generation",
            "GET /status/{job_id}": "Check job status",
            "GET /download/{job_id}/{filename}": "Download generated video",
            "GET /health": "Service health check"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=API_PORT)