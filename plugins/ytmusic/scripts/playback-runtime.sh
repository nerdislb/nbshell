#!/usr/bin/env bash
set -euo pipefail

action=${1:-}
if (( $# != 1 )); then
  echo "Usage: scripts/playback-runtime.sh check|start|stop|status|unit" >&2
  exit 2
fi

venv_python="$HOME/.local/share/omarchy-ytmusic/venv/bin/python"
backend_script="$HOME/.local/lib/omarchy-ytmusic/server.py"
unit=omarchy-ytmusic.service

unit_exists() {
  systemctl --user cat "$1" >/dev/null 2>&1
}

runtime_ready() {
  [[ -x $venv_python && -f $backend_script ]] && unit_exists "$unit" \
    && command -v mpv >/dev/null 2>&1 && command -v yt-dlp >/dev/null 2>&1
}

case $action in
  check)
    runtime_ready
    ;;
  start)
    runtime_ready || {
      echo "playback-runtime.sh: YouTube Music playback is not installed yet" >&2
      exit 1
    }
    systemctl --user start "$unit"
    ;;
  stop)
    systemctl --user stop "$unit" 2>/dev/null || true
    ;;
  status)
    runtime_ready || exit 1
    systemctl --user is-active "$unit"
    ;;
  unit)
    runtime_ready || exit 1
    printf '%s\n' "$unit"
    ;;
  *)
    echo "playback-runtime.sh: unknown action: $action" >&2
    exit 2
    ;;
esac
