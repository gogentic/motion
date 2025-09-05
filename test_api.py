#!/usr/bin/env python3
"""Test script for ComfyUI API - Simple text to image generation"""

import json
import requests
import uuid
import time
import sys

# ComfyUI API URL
API_URL = "http://localhost:9188"

def create_simple_workflow(prompt_text="A beautiful sunset over mountains"):
    """Create a simple text-to-image workflow for testing"""
    
    workflow = {
        "1": {
            "inputs": {
                "ckpt_name": "v1-5-pruned-emaonly.safetensors"  # Change to your model
            },
            "class_type": "CheckpointLoaderSimple"
        },
        "2": {
            "inputs": {
                "text": prompt_text,
                "clip": ["1", 1]
            },
            "class_type": "CLIPTextEncode"
        },
        "3": {
            "inputs": {
                "text": "blurry, low quality",
                "clip": ["1", 1]
            },
            "class_type": "CLIPTextEncode"
        },
        "4": {
            "inputs": {
                "width": 512,
                "height": 512,
                "batch_size": 1
            },
            "class_type": "EmptyLatentImage"
        },
        "5": {
            "inputs": {
                "seed": 42,
                "steps": 20,
                "cfg": 7.0,
                "sampler_name": "euler",
                "scheduler": "normal",
                "denoise": 1.0,
                "model": ["1", 0],
                "positive": ["2", 0],
                "negative": ["3", 0],
                "latent_image": ["4", 0]
            },
            "class_type": "KSampler"
        },
        "6": {
            "inputs": {
                "samples": ["5", 0],
                "vae": ["1", 2]
            },
            "class_type": "VAEDecode"
        },
        "7": {
            "inputs": {
                "filename_prefix": "test_api",
                "images": ["6", 0]
            },
            "class_type": "SaveImage"
        }
    }
    
    return workflow

def submit_workflow(workflow):
    """Submit workflow to ComfyUI API"""
    
    # Check if API is ready
    try:
        response = requests.get(f"{API_URL}/system_stats", timeout=5)
        if response.status_code == 200:
            print("✓ ComfyUI API is ready")
        else:
            print("✗ ComfyUI not ready")
            return None
    except Exception as e:
        print(f"✗ Cannot connect to ComfyUI: {e}")
        return None
    
    # Submit the workflow
    prompt_id = str(uuid.uuid4())
    payload = {
        "prompt": workflow,
        "client_id": prompt_id
    }
    
    try:
        response = requests.post(f"{API_URL}/prompt", json=payload, timeout=10)
        if response.status_code == 200:
            result = response.json()
            prompt_id = result.get("prompt_id", prompt_id)
            print(f"✓ Job submitted! Prompt ID: {prompt_id}")
            return prompt_id
        else:
            print(f"✗ Failed to submit: {response.text}")
            return None
    except Exception as e:
        print(f"✗ Error submitting workflow: {e}")
        return None

def check_progress(prompt_id):
    """Check progress of a prompt"""
    
    try:
        response = requests.get(f"{API_URL}/history/{prompt_id}", timeout=5)
        if response.status_code == 200:
            history = response.json()
            if prompt_id in history:
                status = history[prompt_id].get("status", {})
                if status.get("completed"):
                    return "completed"
                elif status.get("status_str"):
                    return status["status_str"]
            return "processing"
        return "unknown"
    except:
        return "error"

def main():
    print("ComfyUI API Test Script")
    print("=" * 40)
    
    # Get available checkpoints
    try:
        response = requests.get(f"{API_URL}/object_info/CheckpointLoaderSimple", timeout=5)
        if response.status_code == 200:
            data = response.json()
            checkpoints = data.get("CheckpointLoaderSimple", {}).get("input", {}).get("required", {}).get("ckpt_name", [[]])[0]
            if checkpoints:
                print(f"Available checkpoints: {', '.join(checkpoints[:3])}")
                if checkpoints:
                    # Use the first available checkpoint
                    checkpoint = checkpoints[0]
                    print(f"Using checkpoint: {checkpoint}")
            else:
                print("No checkpoints found. Please install a model first.")
                return
    except Exception as e:
        print(f"Error getting checkpoints: {e}")
    
    # Create and submit workflow
    prompt = input("\nEnter prompt (or press Enter for default): ").strip()
    if not prompt:
        prompt = "A beautiful sunset over mountains, highly detailed, 8k"
    
    print(f"\nGenerating image with prompt: {prompt}")
    
    workflow = create_simple_workflow(prompt)
    
    # Update with actual checkpoint if found
    if 'checkpoint' in locals():
        workflow["1"]["inputs"]["ckpt_name"] = checkpoint
    
    prompt_id = submit_workflow(workflow)
    
    if prompt_id:
        print("\nProcessing... (this may take 30-60 seconds)")
        
        # Wait for completion
        max_wait = 120
        start_time = time.time()
        
        while time.time() - start_time < max_wait:
            status = check_progress(prompt_id)
            if status == "completed":
                print(f"\n✓ Generation completed!")
                print(f"Check output in: ./output/")
                break
            elif status == "error":
                print("\n✗ Error during generation")
                break
            else:
                print(".", end="", flush=True)
                time.sleep(2)
        else:
            print("\n✗ Timeout waiting for generation")

if __name__ == "__main__":
    main()