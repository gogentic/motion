#!/usr/bin/env python3
"""Test script for Hunyuan video generation through API"""

import json
import requests
import uuid
import time
import sys

# API URL
API_URL = "http://localhost:9000"

def create_hunyuan_workflow(prompt_text="anime style anime girl with massive fennec ears"):
    """Create Hunyuan video workflow in API format"""
    
    # Convert frontend workflow to API format
    workflow = {
        # KSamplerSelect
        "16": {
            "inputs": {"sampler_name": "euler"},
            "class_type": "KSamplerSelect"
        },
        # BasicScheduler
        "17": {
            "inputs": {
                "scheduler": "simple",
                "steps": 20,
                "denoise": 1,
                "model": ["12", 0]
            },
            "class_type": "BasicScheduler"
        },
        # FluxGuidance
        "26": {
            "inputs": {
                "guidance": 6,
                "conditioning": ["44", 0]
            },
            "class_type": "FluxGuidance"
        },
        # EmptyHunyuanLatentVideo
        "45": {
            "inputs": {
                "width": 848,
                "height": 480,
                "length": 73,
                "batch_size": 1
            },
            "class_type": "EmptyHunyuanLatentVideo"
        },
        # BasicGuider
        "22": {
            "inputs": {
                "model": ["67", 0],
                "conditioning": ["26", 0]
            },
            "class_type": "BasicGuider"
        },
        # ModelSamplingSD3
        "67": {
            "inputs": {
                "shift": 7,
                "model": ["12", 0]
            },
            "class_type": "ModelSamplingSD3"
        },
        # VAELoader
        "10": {
            "inputs": {
                "vae_name": "hunyuan_video_vae_bf16.safetensors"
            },
            "class_type": "VAELoader"
        },
        # DualCLIPLoader
        "11": {
            "inputs": {
                "clip_name1": "clip_l.safetensors",
                "clip_name2": "llava_llama3_fp8_scaled.safetensors",
                "type": "hunyuan_video"
            },
            "class_type": "DualCLIPLoader"
        },
        # VAEDecodeTiled
        "73": {
            "inputs": {
                "tile_size": 256,
                "overlap": 64,
                "temporal_size": 16,
                "temporal_overlap": 4,
                "samples": ["13", 0],
                "vae": ["10", 0]
            },
            "class_type": "VAEDecodeTiled"
        },
        # UNETLoader
        "12": {
            "inputs": {
                "unet_name": "hunyuan_video/hunyuan_video_t2v_720p_bf16.safetensors",
                "weight_dtype": "default"
            },
            "class_type": "UNETLoader"
        },
        # SamplerCustomAdvanced
        "13": {
            "inputs": {
                "noise": ["25", 0],
                "guider": ["22", 0],
                "sampler": ["16", 0],
                "sigmas": ["17", 0],
                "latent_image": ["45", 0]
            },
            "class_type": "SamplerCustomAdvanced"
        },
        # CLIPTextEncode (Positive Prompt)
        "44": {
            "inputs": {
                "text": prompt_text,
                "clip": ["11", 0]
            },
            "class_type": "CLIPTextEncode"
        },
        # SaveAnimatedWEBP
        "75": {
            "inputs": {
                "filename_prefix": "motion_api_test",
                "fps": 24,
                "lossless": False,
                "quality": 80,
                "method": "default",
                "images": ["73", 0]
            },
            "class_type": "SaveAnimatedWEBP"
        },
        # RandomNoise
        "25": {
            "inputs": {
                "noise_seed": 1,
                "seed_control_mode": "randomize"
            },
            "class_type": "RandomNoise"
        }
    }
    
    return workflow

def submit_job(prompt="A beautiful animated scene with flowing water"):
    """Submit video generation job to API"""
    
    print(f"\nSubmitting job with prompt: {prompt}")
    
    workflow = create_hunyuan_workflow(prompt)
    
    payload = {
        "script": prompt,  # The API expects a script field
        "workflow": workflow  # Include custom workflow
    }
    
    try:
        response = requests.post(f"{API_URL}/generate", json=payload, timeout=10)
        if response.status_code == 200:
            result = response.json()
            job_id = result.get("job_id")
            print(f"✓ Job submitted! Job ID: {job_id}")
            return job_id
        else:
            print(f"✗ Failed to submit: {response.text}")
            return None
    except Exception as e:
        print(f"✗ Error submitting job: {e}")
        return None

def check_status(job_id):
    """Check job status"""
    
    try:
        response = requests.get(f"{API_URL}/status/{job_id}", timeout=5)
        if response.status_code == 200:
            status = response.json()
            return status
        else:
            print(f"✗ Failed to get status: {response.text}")
            return None
    except Exception as e:
        print(f"✗ Error checking status: {e}")
        return None

def main():
    print("Hunyuan Video Generation API Test")
    print("=" * 40)
    
    # Check API health first
    try:
        response = requests.get(f"{API_URL}/health", timeout=5)
        if response.status_code == 200:
            print("✓ API is healthy")
        else:
            print("✗ API health check failed")
            return
    except Exception as e:
        print(f"✗ Cannot connect to API: {e}")
        return
    
    # Submit job
    prompt = input("\nEnter prompt (or press Enter for default): ").strip()
    if not prompt:
        prompt = "anime style anime girl with massive fennec ears and one big fluffy tail, blonde hair, blue eyes, walking in beautiful outdoor scenery"
    
    job_id = submit_job(prompt)
    
    if job_id:
        print("\nMonitoring job progress...")
        print("This may take 2-3 minutes for video generation...")
        
        max_wait = 600  # 10 minutes for Hunyuan video generation
        start_time = time.time()
        last_status = None
        
        while time.time() - start_time < max_wait:
            status = check_status(job_id)
            if status:
                current_status = status.get("status")
                if current_status != last_status:
                    print(f"\nStatus: {current_status}")
                    if status.get("progress"):
                        print(f"Progress: {status['progress']}%")
                    last_status = current_status
                
                if current_status == "completed":
                    print(f"\n✓ Video generation completed!")
                    if status.get("outputs"):
                        print(f"Outputs: {json.dumps(status['outputs'], indent=2)}")
                    break
                elif current_status == "failed":
                    print(f"\n✗ Job failed: {status.get('error', 'Unknown error')}")
                    break
            
            print(".", end="", flush=True)
            time.sleep(5)
        else:
            print("\n✗ Timeout waiting for job completion")

if __name__ == "__main__":
    main()