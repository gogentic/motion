#!/usr/bin/env python3
"""
Example client for MOTION Video Generation API
"""

import requests
import json
import time
import sys
import os
from pathlib import Path

API_URL = os.getenv("API_URL", "http://localhost:9000")

def submit_script(script_text, **kwargs):
    """Submit a script for video generation"""
    
    payload = {
        "script": script_text,
        "clips_per_minute": kwargs.get("clips_per_minute", 2),
        "clip_duration": kwargs.get("clip_duration", 6.5),
        "style": kwargs.get("style", "cinematic"),
        "resolution": kwargs.get("resolution", "512x512"),
        "fps": kwargs.get("fps", 8)
    }
    
    response = requests.post(f"{API_URL}/generate", json=payload)
    
    if response.status_code == 200:
        result = response.json()
        print(f"Job submitted successfully!")
        print(f"Job ID: {result['job_id']}")
        print(f"Status: {result['status']}")
        print(f"Message: {result['message']}")
        return result['job_id']
    else:
        print(f"Error submitting job: {response.text}")
        return None

def check_status(job_id):
    """Check the status of a job"""
    
    response = requests.get(f"{API_URL}/status/{job_id}")
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f"Error checking status: {response.text}")
        return None

def download_outputs(job_id, output_dir="./downloads"):
    """Download all outputs for a completed job"""
    
    status = check_status(job_id)
    if not status or status['status'] != 'completed':
        print("Job not completed yet")
        return False
    
    output_dir = Path(output_dir)
    output_dir.mkdir(exist_ok=True)
    
    for file_path in status['output_files']:
        filename = Path(file_path).name
        
        response = requests.get(f"{API_URL}/download/{job_id}/{filename}")
        
        if response.status_code == 200:
            save_path = output_dir / filename
            with open(save_path, 'wb') as f:
                f.write(response.content)
            print(f"Downloaded: {save_path}")
        else:
            print(f"Failed to download {filename}")
    
    return True

def wait_for_completion(job_id, check_interval=5, timeout=600):
    """Wait for a job to complete with progress updates"""
    
    start_time = time.time()
    last_progress = -1
    
    while time.time() - start_time < timeout:
        status = check_status(job_id)
        
        if not status:
            time.sleep(check_interval)
            continue
        
        if status['progress'] != last_progress:
            print(f"\rProgress: {status['progress']:.1f}% "
                  f"({status['clips_generated']}/{status['total_clips']} clips)", 
                  end='', flush=True)
            last_progress = status['progress']
        
        if status['status'] == 'completed':
            print("\n✓ Job completed successfully!")
            return True
        elif status['status'] == 'failed':
            print(f"\n✗ Job failed: {status.get('error', 'Unknown error')}")
            return False
        
        time.sleep(check_interval)
    
    print("\n✗ Job timed out")
    return False

def main():
    # Example scripts
    scripts = {
        "nature": """
        A serene mountain landscape at dawn.
        The sun slowly rises behind snow-capped peaks.
        Eagles soar through the morning mist.
        A river flows through the valley below.
        Wildflowers bloom in the alpine meadow.
        """,
        
        "scifi": """
        A futuristic cityscape with flying vehicles.
        Neon lights illuminate the night sky.
        Robots walk alongside humans on busy streets.
        Holographic advertisements float in the air.
        A massive space station orbits overhead.
        """,
        
        "fantasy": """
        An ancient wizard's tower rises from misty woods.
        Dragons circle the tower's glowing peak.
        Magical runes pulse with ethereal light.
        A unicorn drinks from a crystal clear stream.
        Fireflies dance through the enchanted forest.
        """
    }
    
    print("MOTION Video Generation API Test")
    print("=" * 40)
    
    # Check API health
    try:
        response = requests.get(f"{API_URL}/health")
        health = response.json()
        print(f"API Status: {health['status']}")
        print(f"ComfyUI: {health['comfyui']}")
    except:
        print("Error: Cannot connect to API. Is the service running?")
        sys.exit(1)
    
    print("\nAvailable test scripts:")
    for i, (name, _) in enumerate(scripts.items(), 1):
        print(f"  {i}. {name}")
    
    choice = input("\nSelect script (1-3) or press Enter for custom: ").strip()
    
    if choice in ['1', '2', '3']:
        script_name = list(scripts.keys())[int(choice) - 1]
        script_text = scripts[script_name]
        print(f"\nUsing {script_name} script")
    else:
        script_text = input("\nEnter your custom script:\n")
    
    # Submit job
    print("\n" + "=" * 40)
    print("Submitting script for video generation...")
    
    job_id = submit_script(
        script_text,
        clips_per_minute=2,
        clip_duration=5,
        style="cinematic, high quality, detailed",
        resolution="512x512",
        fps=8
    )
    
    if not job_id:
        print("Failed to submit job")
        sys.exit(1)
    
    # Wait for completion
    print("\nWaiting for video generation...")
    
    if wait_for_completion(job_id):
        # Download outputs
        print("\nDownloading generated videos...")
        download_outputs(job_id)
        print("\n✓ All done! Check the downloads folder for your videos.")
    else:
        print("\nJob did not complete successfully")

if __name__ == "__main__":
    main()