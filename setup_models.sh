#!/bin/bash

echo "Setting up MOTION Video Generation Service"
echo "=========================================="

MODEL_DIR="./ComfyUI/models"
CUSTOM_NODES_DIR="./ComfyUI/custom_nodes"

mkdir -p $MODEL_DIR/checkpoints
mkdir -p $MODEL_DIR/vae
mkdir -p $MODEL_DIR/animatediff_models
mkdir -p $MODEL_DIR/animatediff_motion_lora
mkdir -p $MODEL_DIR/controlnet
mkdir -p ./input
mkdir -p ./output
mkdir -p ./workflows

echo "Installing required ComfyUI custom nodes..."

cd $CUSTOM_NODES_DIR

if [ ! -d "ComfyUI-AnimateDiff-Evolved" ]; then
    echo "Installing AnimateDiff..."
    git clone https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved.git
fi

if [ ! -d "ComfyUI-VideoHelperSuite" ]; then
    echo "Installing Video Helper Suite..."
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
fi

if [ ! -d "ComfyUI-Manager" ]; then
    echo "Installing ComfyUI Manager..."
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
fi

cd ../..

echo ""
echo "Model Download Instructions"
echo "============================"
echo ""
echo "You need to download the following models and place them in the specified directories:"
echo ""
echo "1. Stable Diffusion XL Base Model:"
echo "   Download: https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/blob/main/sd_xl_base_1.0.safetensors"
echo "   Place in: $MODEL_DIR/checkpoints/"
echo ""
echo "2. AnimateDiff Motion Module:"
echo "   Download: https://huggingface.co/guoyww/animatediff/blob/main/mm_sd_v15_v2.ckpt"
echo "   Place in: $MODEL_DIR/animatediff_models/"
echo ""
echo "3. VAE (optional but recommended):"
echo "   Download: https://huggingface.co/stabilityai/sd-vae-ft-mse-original/blob/main/vae-ft-mse-840000-ema-pruned.safetensors"
echo "   Place in: $MODEL_DIR/vae/"
echo ""
echo "Alternative: You can use smaller SD 1.5 models for faster generation:"
echo "   Download: https://huggingface.co/runwayml/stable-diffusion-v1-5/blob/main/v1-5-pruned-emaonly.safetensors"
echo "   Place in: $MODEL_DIR/checkpoints/"
echo ""

echo "Creating model download helper script..."
cat > download_models.py << 'EOF'
import os
import requests
from tqdm import tqdm
import argparse

def download_file(url, dest_path):
    response = requests.get(url, stream=True)
    total_size = int(response.headers.get('content-length', 0))
    
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    
    with open(dest_path, 'wb') as file:
        with tqdm(total=total_size, unit='iB', unit_scale=True) as pbar:
            for data in response.iter_content(chunk_size=8192):
                size = file.write(data)
                pbar.update(size)

models = {
    "sd15": {
        "url": "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors",
        "path": "./ComfyUI/models/checkpoints/v1-5-pruned-emaonly.safetensors"
    },
    "animatediff": {
        "url": "https://huggingface.co/guoyww/animatediff/resolve/main/mm_sd_v15_v2.ckpt",
        "path": "./ComfyUI/models/animatediff_models/mm_sd_v15_v2.ckpt"
    },
    "vae": {
        "url": "https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors",
        "path": "./ComfyUI/models/vae/vae-ft-mse-840000-ema-pruned.safetensors"
    }
}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Download models for MOTION")
    parser.add_argument("--model", choices=list(models.keys()) + ["all"], default="all")
    args = parser.parse_args()
    
    if args.model == "all":
        for name, info in models.items():
            print(f"Downloading {name}...")
            download_file(info["url"], info["path"])
    else:
        info = models[args.model]
        print(f"Downloading {args.model}...")
        download_file(info["url"], info["path"])
    
    print("Download complete!")
EOF

echo ""
echo "You can use 'python download_models.py' to download the models automatically"
echo "(requires 'pip install tqdm requests')"
echo ""

echo "Setup script complete!"
echo ""
echo "Next steps:"
echo "1. Download the required models (see instructions above)"
echo "2. Build and run with Docker Compose: docker-compose up --build"
echo "3. Access the API at http://localhost:8000"
echo "4. Submit scripts for video generation!"