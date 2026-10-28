# AI Station RunPod

Portable desktop image for GPU pods. **Experimental: not yet verified by a successful build + runtime test.**

Includes XFCE, VNC/noVNC, ComfyUI, LU, ffmpeg, mpv and VLC. Use a persistent Network Volume at `/workspace`; models at `/workspace/ai-station/models` and data in `/workspace/ai-station/{input,output}`. Avoid running venv/SQLite directly on GeeseFS.

Set `VNC_PASSWORD` through RunPod environment secrets; access noVNC via SSH tunnel to localhost:6080, not the public Internet. Port 8188 likewise binds locally. Use `ai-station status` and `ai-station backup` before stopping. Verify backup exists before terminating a pod.

GitHub Actions builds/pushes `ghcr.io/davide122/ai-station-runpod:latest` on changes; for private GHCR package configure pull credentials or make only the container package public. Repository privacy and package privacy are separate. This image is not guaranteed production-ready until a clean build and Pod deployment succeed.
