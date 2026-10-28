#!/usr/bin/env bash
set -Eeuo pipefail
/start.sh >/var/log/runpod-base.log 2>&1 &
base_pid=$!
/usr/local/bin/ai-station start || echo "AI Station start failed; inspect /var/log/ai-station"
wait "$base_pid"
