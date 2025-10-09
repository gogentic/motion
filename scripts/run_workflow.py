#!/usr/bin/env python3
"""
Run ComfyUI workflows headless via the API.

Usage:
    python scripts/run_workflow.py workflows/hunyuan_safe_settings_api.json
    python scripts/run_workflow.py workflows/hunyuan_safe_settings_api.json --prompt "A beautiful sunset"
    python scripts/run_workflow.py workflows/hunyuan_safe_settings_api.json --monitor
"""

import json
import sys
import time
import uuid
import argparse
import requests
from pathlib import Path


class ComfyUIClient:
    def __init__(self, host="localhost", port=9188):
        self.base_url = f"http://{host}:{port}"
        
    def load_workflow(self, workflow_path):
        """Load a workflow JSON file."""
        with open(workflow_path, 'r') as f:
            return json.load(f)
    
    def prepare_workflow(self, workflow, text_prompt=None):
        """Prepare workflow with proper model paths and optional text prompt."""
        # Remove UI-only nodes
        for node_id in list(workflow.keys()):
            if isinstance(workflow[node_id], dict):
                if workflow[node_id].get('class_type') == 'Note':
                    del workflow[node_id]
        
        # Update model paths based on what's available
        for node_id, node_data in workflow.items():
            if not isinstance(node_data, dict):
                continue
                
            class_type = node_data.get('class_type')
            
            # VAE Loader
            if class_type == 'VAELoader':
                if 'inputs' not in node_data:
                    node_data['inputs'] = {}
                node_data['inputs']['vae_name'] = 'hunyuan_video_vae_bf16.safetensors'
            
            # UNET Loader
            elif class_type == 'UNETLoader':
                if 'inputs' not in node_data:
                    node_data['inputs'] = {}
                # Use available Hunyuan model
                node_data['inputs']['unet_name'] = 'hunyuan_video/hunyuan_video_t2v_720p_bf16.safetensors'
                node_data['inputs']['weight_dtype'] = 'default'
            
            # Dual CLIP Loader
            elif class_type == 'DualCLIPLoader':
                if 'inputs' not in node_data:
                    node_data['inputs'] = {}
                node_data['inputs']['clip_name1'] = 'clip_l.safetensors'
                node_data['inputs']['clip_name2'] = 'llava_llama3_fp8_scaled.safetensors'
                node_data['inputs']['type'] = 'hunyuan_video'
            
            # Text prompt
            elif class_type == 'CLIPTextEncode' and text_prompt:
                if 'inputs' not in node_data:
                    node_data['inputs'] = {}
                node_data['inputs']['text'] = text_prompt
            
            # Save nodes - ensure they have required inputs
            elif class_type == 'SaveAnimatedWEBP':
                if 'inputs' not in node_data:
                    node_data['inputs'] = {}
                if 'filename_prefix' not in node_data['inputs']:
                    node_data['inputs']['filename_prefix'] = 'comfyui_output'
                if 'fps' not in node_data['inputs']:
                    node_data['inputs']['fps'] = 8
                if 'method' not in node_data['inputs']:
                    node_data['inputs']['method'] = 'default'
                if 'quality' not in node_data['inputs']:
                    node_data['inputs']['quality'] = 85
                if 'lossless' not in node_data['inputs']:
                    node_data['inputs']['lossless'] = False
            
            # Video dimensions
            elif class_type == 'EmptyHunyuanLatentVideo':
                if 'inputs' not in node_data:
                    node_data['inputs'] = {}
                if 'width' not in node_data['inputs']:
                    node_data['inputs']['width'] = 848
                if 'height' not in node_data['inputs']:
                    node_data['inputs']['height'] = 480
                if 'length' not in node_data['inputs']:
                    node_data['inputs']['length'] = 49
                if 'batch_size' not in node_data['inputs']:
                    node_data['inputs']['batch_size'] = 1
        
        return workflow
    
    def submit_workflow(self, workflow):
        """Submit workflow to ComfyUI API."""
        api_request = {
            'prompt': workflow,
            'client_id': str(uuid.uuid4())
        }
        
        response = requests.post(f"{self.base_url}/prompt", json=api_request)
        return response.json()
    
    def get_queue_status(self):
        """Get current queue status."""
        response = requests.get(f"{self.base_url}/queue")
        return response.json()
    
    def get_history(self, prompt_id):
        """Get generation history for a prompt."""
        response = requests.get(f"{self.base_url}/history/{prompt_id}")
        return response.json()
    
    def monitor_generation(self, prompt_id, timeout=300):
        """Monitor generation progress."""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            # Check queue
            queue = self.get_queue_status()
            
            # Check if running
            for item in queue.get('queue_running', []):
                if item[1] == prompt_id:
                    print(f"⏳ Processing... (elapsed: {int(time.time() - start_time)}s)", end='\r')
                    break
            
            # Check if pending
            for i, item in enumerate(queue.get('queue_pending', [])):
                if item[1] == prompt_id:
                    print(f"⏳ In queue position {i+1}... (elapsed: {int(time.time() - start_time)}s)", end='\r')
                    break
            
            # Check history for completion
            history = self.get_history(prompt_id)
            if prompt_id in history:
                status = history[prompt_id].get('status', {})
                if status.get('completed'):
                    print(f"\n✅ Generation completed in {int(time.time() - start_time)} seconds!")
                    
                    # Show outputs
                    outputs = history[prompt_id].get('outputs', {})
                    for node_id, output in outputs.items():
                        if 'images' in output:
                            for img in output['images']:
                                filename = img.get('filename', 'unknown')
                                print(f"  📁 Output: {filename}")
                    return True
                elif 'error' in status:
                    print(f"\n❌ Error: {status.get('error')}")
                    return False
            
            time.sleep(2)
        
        print(f"\n⚠️ Timeout after {timeout} seconds")
        return False


def main():
    parser = argparse.ArgumentParser(description='Run ComfyUI workflows headless')
    parser.add_argument('workflow', help='Path to workflow JSON file')
    parser.add_argument('--prompt', help='Text prompt to use')
    parser.add_argument('--monitor', action='store_true', help='Monitor generation progress')
    parser.add_argument('--host', default='localhost', help='ComfyUI host')
    parser.add_argument('--port', type=int, default=9188, help='ComfyUI port')
    
    args = parser.parse_args()
    
    # Check workflow exists
    workflow_path = Path(args.workflow)
    if not workflow_path.exists():
        print(f"❌ Workflow not found: {workflow_path}")
        sys.exit(1)
    
    # Initialize client
    client = ComfyUIClient(args.host, args.port)
    
    # Load and prepare workflow
    print(f"📄 Loading workflow: {workflow_path}")
    workflow = client.load_workflow(workflow_path)
    workflow = client.prepare_workflow(workflow, args.prompt)
    
    if args.prompt:
        print(f"📝 Using prompt: {args.prompt}")
    
    # Submit workflow
    print("🚀 Submitting workflow...")
    result = client.submit_workflow(workflow)
    
    if 'error' in result:
        print(f"❌ Error: {result['error'].get('message', 'Unknown error')}")
        if 'details' in result['error']:
            print(f"   Details: {result['error']['details']}")
        sys.exit(1)
    
    prompt_id = result.get('prompt_id')
    queue_number = result.get('number')
    
    print(f"✅ Queued successfully!")
    print(f"   Prompt ID: {prompt_id}")
    print(f"   Queue number: {queue_number}")
    
    # Monitor if requested
    if args.monitor:
        print("\n📊 Monitoring progress...")
        success = client.monitor_generation(prompt_id)
        if success:
            print(f"\n🎉 Check output folder: /home/ira/dev/MOTION/output/")
    else:
        print(f"\nTo monitor progress, run:")
        print(f"  python {sys.argv[0]} {args.workflow} --monitor")
        print(f"\nOr check output folder: /home/ira/dev/MOTION/output/")


if __name__ == "__main__":
    main()