#!/usr/bin/env bash
set -Eeuo pipefail
BASE=/workspace/ai-station
HOME_AI=/home/ai
SCRATCH=/var/lib/ai-station
LOG=/var/log/ai-station
mkdir -p "$LOG" "$SCRATCH"/{input,output,comfy-user}

require_volume() {
  mountpoint -q /workspace || { echo "ERROR: /workspace is not mounted"; return 1; }
}

init() {
  require_volume
  mkdir -p "$BASE"/{models,input,output,backups,downloads}
  mkdir -p "$HOME_AI"/{Desktop,.vnc,.config,.local}
  # Restore once per container: never overwrite files from an active session.
  if [ ! -e "$SCRATCH/.restored" ]; then
    if [ -s "$BASE/backups/home-ai.tar.gz" ]; then
      tar -xzf "$BASE/backups/home-ai.tar.gz" -C "$HOME_AI" --no-same-owner
    fi
    touch "$SCRATCH/.restored"
  fi
  chown -R ai:ai "$HOME_AI" "$SCRATCH"
  cat > "$HOME_AI/.vnc/xstartup" <<'EOS'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export LIBGL_ALWAYS_SOFTWARE=1
exec dbus-run-session -- xfce4-session
EOS
  chmod 755 "$HOME_AI/.vnc/xstartup"
  if [ -z "${VNC_PASSWORD:-}" ]; then
    if [ ! -s "$HOME_AI/.vnc/passwd" ]; then
      echo "ERROR: set VNC_PASSWORD in RunPod environment variables (once)."
      return 1
    fi
  else
    printf '%s\n' "$VNC_PASSWORD" | runuser -u ai -- tigervncpasswd -f >"$HOME_AI/.vnc/passwd"
  fi
  chmod 600 "$HOME_AI/.vnc/passwd"
  chown -R ai:ai "$HOME_AI/.vnc"
  ln -sfn "$SCRATCH/output" "$HOME_AI/Desktop/Video-AI"
  ln -sfn "$SCRATCH/input" "$HOME_AI/Desktop/Input-AI"
  rsync -r --ignore-existing "$BASE/output/" "$SCRATCH/output/"
  rsync -r --ignore-existing "$BASE/input/" "$SCRATCH/input/"
  cat > /opt/ComfyUI/extra_model_paths.yaml <<EOS
station:
  base_path: $BASE/models
  checkpoints: checkpoints
  diffusion_models: diffusion_models
  text_encoders: text_encoders
  vae: vae
  loras: loras
  controlnet: controlnet
  upscale_models: upscale_models
EOS
}

start() {
  init
  if ! ss -lnt | grep -q ':5901 '; then
    runuser -u ai -- env LIBGL_ALWAYS_SOFTWARE=1 tigervncserver :1 -localhost yes -geometry 1600x900 -depth 24 -extension GLX >"$LOG/vnc.log" 2>&1
  fi
  if ! ss -lnt | grep -q ':6080 '; then
    websockify --web=/usr/share/novnc 127.0.0.1:6080 127.0.0.1:5901 >"$LOG/novnc.log" 2>&1 &
  fi
  if ! ss -lnt | grep -q ':8188 '; then
    (
      cd /opt/ComfyUI
      runuser -u ai -- /opt/comfy-venv/bin/python main.py --user-directory "$SCRATCH/comfy-user" --listen 127.0.0.1 --port 8188 --output-directory "$SCRATCH/output" --input-directory "$SCRATCH/input" --extra-model-paths-config /opt/ComfyUI/extra_model_paths.yaml
    ) >"$LOG/comfyui.log" 2>&1 &
  fi
  if ! pgrep -u ai -f 'locally-uncensored|locally_uncensored' >/dev/null; then
    LU_BIN=$(command -v locally-uncensored || command -v locally-uncensored-app || true)
    if [ -z "$LU_BIN" ]; then echo "LU executable not found" >"$LOG/lu.log"
    else
      runuser -u ai -- env DISPLAY=:1 HOME="$HOME_AI" XDG_RUNTIME_DIR=/tmp/runtime-ai LIBGL_ALWAYS_SOFTWARE=1 "$LU_BIN" >"$LOG/lu.log" 2>&1 &
    fi
  fi
  echo "AI Station services launched. Check ai-station status."
}

backup() {
  require_volume
  mkdir -p "$BASE/backups" "$HOME_AI/.local"
  # Serialize backups; GeeseFS does not implement full POSIX filesystem semantics.
  flock -n /tmp/ai-station-backup.lock bash -c '
    set -e
    tar -czf "$1/backups/home-ai.tar.gz.part" -C "$2" .config .local .vnc Desktop
    mv "$1/backups/home-ai.tar.gz.part" "$1/backups/home-ai.tar.gz"
    rsync -r "$3/output/" "$1/output/"
    rsync -r "$3/input/" "$1/input/"
  ' _ "$BASE" "$HOME_AI" "$SCRATCH"
  echo "Backup written to $BASE/backups"
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
