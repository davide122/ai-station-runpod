#!/usr/bin/env bash
set -Eeuo pipefail
BASE=/workspace/ai-station
HOME_AI=/home/ai
SCRATCH=/var/lib/ai-station
LOG=/var/log/ai-station
mkdir -p "$LOG" "$SCRATCH"/{input,output}
require_volume() {
  if ! mountpoint -q /workspace; then echo "ERROR: mount the persistent volume at /workspace"; exit 1; fi
}
init() {
  require_volume
  mkdir -p "$BASE"/{models,input,output,backups,downloads}
  mkdir -p "$HOME_AI"/{Desktop,.vnc,.config}
  if [ -f "$BASE/backups/home-ai.tar.gz" ]; then tar -xzf "$BASE/backups/home-ai.tar.gz" -C "$HOME_AI" --no-same-owner; fi
  chown -R ai:ai "$HOME_AI" "$SCRATCH"
  cat > "$HOME_AI/.vnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session startxfce4
EOF
  chmod +x "$HOME_AI/.vnc/xstartup"
  if [ -z "${VNC_PASSWORD:-}" ]; then echo "Set VNC_PASSWORD using RunPod environment secrets"; return 1; fi
  printf '%s\n' "$VNC_PASSWORD" | runuser -u ai -- vncpasswd -f > "$HOME_AI/.vnc/passwd"
  chmod 600 "$HOME_AI/.vnc/passwd"
  chown -R ai:ai "$HOME_AI/.vnc"
  ln -sfn "$SCRATCH/output" "$HOME_AI/Desktop/Video-AI"
  ln -sfn "$SCRATCH/input" "$HOME_AI/Desktop/Input-AI"
  rsync -r --ignore-existing "$BASE/output/" "$SCRATCH/output/" || true
  rsync -r --ignore-existing "$BASE/input/" "$SCRATCH/input/" || true
  cat > /opt/ComfyUI/extra_model_paths.yaml <<EOF
station:
  base_path: $BASE/models
  checkpoints: checkpoints
  diffusion_models: diffusion_models
  text_encoders: text_encoders
  vae: vae
  loras: loras
  controlnet: controlnet
  upscale_models: upscale_models
EOF
}
start() {
 init
 runuser -u ai -- tigervncserver :1 -localhost yes -geometry 1600x900 -depth 24 >"$LOG/vnc.log" 2>&1 || true
 websockify --web=/usr/share/novnc 127.0.0.1:6080 127.0.0.1:5901 >"$LOG/novnc.log" 2>&1 &
 if ! curl -sf http://127.0.0.1:8188/system_stats >/dev/null; then
  cd /opt/ComfyUI
  runuser -u ai -- /opt/comfy-venv/bin/python main.py --listen 127.0.0.1 --port 8188 --output-directory "$SCRATCH/output" --input-directory "$SCRATCH/input" --extra-model-paths-config /opt/ComfyUI/extra_model_paths.yaml >"$LOG/comfyui.log" 2>&1 &
 fi
 LU_BIN=$(command -v locally-uncensored || command -v locally-uncensored-app || true)
 if [ -n "$LU_BIN" ]; then
  runuser -u ai -- env DISPLAY=:1 HOME="$HOME_AI" "$LU_BIN" >"$LOG/lu.log" 2>&1 &
 else
  echo "LU executable not found; check installed .deb package" >"$LOG/lu.log"
 fi
 echo "AI Station startup attempted. Check logs with: ai-station status"
}
backup() {
 require_volume
 mkdir -p "$BASE/backups"
 # Snapshot home rather than moving SQLite browser databases to non-POSIX GeeseFS.
 tar -czf "$BASE/backups/home-ai.tar.gz.part" -C "$HOME_AI" .config .local .vnc Desktop 2>"$LOG/backup.log"
 mv "$BASE/backups/home-ai.tar.gz.part" "$BASE/backups/home-ai.tar.gz"
 rsync -r "$SCRATCH/output/" "$BASE/output/"
 rsync -r "$SCRATCH/input/" "$BASE/input/"
 echo "Backup completed; confirm files on persistent storage before terminating."
}
status() {
 findmnt -T /workspace
 df -h / /workspace
 nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
 ss -lntp | grep -E ':(6080|5901|8188|8888|22) ' || true
 ls -lah "$LOG"
}
case "${1:-}" in
 start) start;; backup) backup;; status) status;;
 *) echo 'ai-station start|backup|status'; exit 2;;
esac
