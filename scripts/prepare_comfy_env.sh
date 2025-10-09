#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMFY_DIR="$ROOT_DIR/ComfyUI"
VENV_DIR="$COMFY_DIR/venv"
PYTHON_BIN="$VENV_DIR/bin/python"

if [ ! -d "$COMFY_DIR" ]; then
    echo "Error: ComfyUI directory not found at $COMFY_DIR" >&2
    exit 1
fi

if [ ! -x "$PYTHON_BIN" ]; then
    echo "Creating virtual environment in $VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

MANAGER_REQ="$COMFY_DIR/custom_nodes/ComfyUI-Manager/requirements.txt"
REQ_PATHS=("$COMFY_DIR/requirements.txt")

if [ -f "$ROOT_DIR/requirements-api.txt" ]; then
    REQ_PATHS+=("$ROOT_DIR/requirements-api.txt")
fi

if [ -f "$MANAGER_REQ" ]; then
    REQ_PATHS+=("$MANAGER_REQ")
fi

REQ_DIGEST=$(python3 - <<'PY' "${REQ_PATHS[@]}"
import hashlib
import sys

hasher = hashlib.sha256()
for path in sys.argv[1:]:
    with open(path, 'rb') as handle:
        hasher.update(handle.read())
print(hasher.hexdigest())
PY
)

STAMP_FILE="$COMFY_DIR/.venv_requirements.sha256"
need_install=1
if [ -f "$STAMP_FILE" ]; then
    current_digest="$(cat "$STAMP_FILE")"
    if [ "$current_digest" = "$REQ_DIGEST" ]; then
        need_install=0
    fi
fi

if [ "$need_install" -eq 1 ]; then
    for req_path in "${REQ_PATHS[@]}"; do
        "$PYTHON_BIN" -m pip install --no-input -r "$req_path"
    done
    echo "$REQ_DIGEST" > "$STAMP_FILE"
fi

EXTRA_PATHS_FILE="$COMFY_DIR/extra_model_paths.yaml"
cat <<'YAML' > "$EXTRA_PATHS_FILE"
comfyui_repo:
    base_path: .
    is_default: true
    checkpoints: models/checkpoints
    clip: models/clip
    clip_vision: models/clip_vision
    configs: models/configs
    controlnet: models/controlnet
    diffusion_models: |
        models/diffusion_models
        models/unet
    embeddings: models/embeddings
    hypernetworks: models/hypernetworks
    loras: models/loras
    model_patches: models/model_patches
    photomaker: models/photomaker
    style_models: models/style_models
    text_encoders: |
        models/text_encoders
        models/clip
    upscale_models: models/upscale_models
    vae: models/vae
    vae_approx: models/vae_approx
shared_models:
    base_path: ..
    checkpoints: models/checkpoints
    diffusion_models: models/diffusion_models
    animatediff_models: models/animatediff_models
    animatediff_motion_lora: models/animatediff_motion_lora
    text_encoders: models/text_encoders
    vae: models/vae
shared_custom_nodes:
    base_path: ..
    custom_nodes: |
        custom_nodes
        custom_nodes_local
YAML

export ROOT_DIR
export COMFY_DIR
"$PYTHON_BIN" <<'PY'
import os
from pathlib import Path

root = Path(os.environ['ROOT_DIR'])
comfy_dir = Path(os.environ['COMFY_DIR'])
shared_workflows = root / 'workflows'
local_workflows = comfy_dir / 'workflows'

if local_workflows.is_symlink():
    # Leave existing symlink in place so writes go to shared folder
    target = local_workflows.resolve()
    shared_workflows = target
elif not local_workflows.exists():
    local_workflows.mkdir(parents=True, exist_ok=True)

if shared_workflows.exists() and not local_workflows.is_symlink():
    for item in shared_workflows.iterdir():
        link = local_workflows / item.name
        if link.exists() or link.is_symlink():
            continue
        if item.is_dir():
            try:
                link.symlink_to(item, target_is_directory=True)
            except OSError:
                continue
        else:
            try:
                link.symlink_to(item)
            except OSError:
                continue
PY

UNWRITABLE=()
for shared in models input output workflows custom_nodes user_data; do
    path="$ROOT_DIR/$shared"
    if [ -d "$path" ] && [ ! -w "$path" ]; then
        UNWRITABLE+=("$path")
    fi
done

if [ ${#UNWRITABLE[@]} -gt 0 ]; then
    echo "" >&2
    echo "The following shared directories are not writable by the current user:" >&2
    for path in "${UNWRITABLE[@]}"; do
        echo "  - $path" >&2
    done
    echo "" >&2
    echo "ComfyUI Manager and the API will not be able to install new models or write outputs until the permissions are fixed." >&2
    echo "Run the following command (once) from $ROOT_DIR to correct ownership:" >&2
    echo "  sudo chown -R $(id -un):$(id -gn) models input output workflows custom_nodes user_data" >&2
    exit 1
fi

echo "ComfyUI environment ready." >&2
