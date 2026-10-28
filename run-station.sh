#!/usr/bin/env bash
set -Eeuo pipefail
/start.sh >/var/log/runpod-base.log 2>&1 &
base_pid=$!
/usr/local/bin/ai-station start >>/var/log/runpod-base.log 2>&1 || echo "AI Station start failed; inspect /var/log/runpod-base.log"
/usr/local/bin/ai-station backup >>/var/log/ai-station/autobackup.log 2>&1 || true
(
  while sleep 900; do
    /usr/local/bin/ai-station backup >>/var/log/ai-station/autobackup.log 2>&1 || true
  done
) &
backup_pid=$!
shutdown() {
  /usr/local/bin/ai-station backup >>/var/log/ai-station/autobackup.log 2>&1 || true
  kill "$backup_pid" 2>/dev/null || true
  kill "$base_pid" 2>/dev/null || true
}
trap shutdown TERM INT
wait "$base_pid"
