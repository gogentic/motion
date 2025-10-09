# Agents Playbook

## Runtime Expectations
- Use the repo-managed virtualenv (`ComfyUI/venv`) for both ComfyUI and the FastAPI service.
- Start/stop through `./start_services.sh` and `./stop_services.sh`; these scripts now call the shared prep helper and run both processes in the same venv.
- The ComfyUI Manager lives at `ComfyUI/custom_nodes/ComfyUI-Manager` and loads automatically after a restart.

## Bringing Services Up
1. (Once per machine) ensure shared folders are writable:
   ```bash
   sudo chown -R ira:ira models input output workflows custom_nodes user_data
   ```
2. Stop any stragglers: `./stop_services.sh`
3. Prepare the environment: `./scripts/prepare_comfy_env.sh`
   - Creates/updates the venv
   - Installs ComfyUI, API, and Manager requirements if the requirement files changed
   - Writes `ComfyUI/extra_model_paths.yaml` pointing at `../models` and both custom-node folders
   - Keeps ComfyUI workflows in sync by linking `ComfyUI/user/default/workflows` to the repo `workflows/`
4. Launch: `./start_services.sh`
   - ComfyUI listens on 9188, FastAPI on 9000
   - Logs land in `comfyui.log` and `api_service.log`
5. Tear down when done: `./stop_services.sh`

## Workflows & Assets
- Authoritative workflows live in the repo `workflows/` directory. Prep/start scripts maintain the symlink into `ComfyUI/user/default/workflows` so they always appear in the sidebar.
- Shared models, VAEs, AnimateDiff assets, etc. are under the top-level `models/` directory. ComfyUI reads them through the `extra_model_paths` config, so there is no need to manually copy files into `ComfyUI/models`.
- Additional custom nodes can go into either `custom_nodes/` (shared) or `custom_nodes_local/` (for experiments). Both paths are advertised to ComfyUI via the prep script.

## Troubleshooting Notes
- If the prep script exits with a permissions warning, rerun the `chown` command above before starting services again.
- `pgrep -fa "ComfyUI/main.py"` and `pgrep -fa "api_service.py"` are handy for finding stray processes if `stop_services.sh` ever misses them.
- After any git pull that touches requirements, re-run `./scripts/prepare_comfy_env.sh` so the venv stays current.
