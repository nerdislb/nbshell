#!/usr/bin/env bash
set -euo pipefail

action=${1:-}
source_root=${2:-}
if [[ -z $action || ( $# -gt 2 ) ]]; then
  echo "Usage: scripts/playback-runtime.sh check|start|stop|restart|health|status|unit [plugin-dir]" >&2
  exit 2
fi

venv_python="$HOME/.local/share/omarchy-ytmusic/venv/bin/python"
lib_dir="$HOME/.local/lib/omarchy-ytmusic"
backend_script="$lib_dir/server.py"
unit=omarchy-ytmusic.service
backend_files=(server.py protocol.py auth.py catalog.py player.py play_history.py)

socket_file() {
  printf '%s/omarchy-ytmusic/backend.sock\n' "${XDG_RUNTIME_DIR:-/tmp}"
}

unit_exists() {
  systemctl --user cat "$1" >/dev/null 2>&1
}

runtime_ready() {
  [[ -x $venv_python && -f $backend_script ]] && unit_exists "$unit" \
    && command -v mpv >/dev/null 2>&1 && command -v yt-dlp >/dev/null 2>&1
}

compile_backend() {
  [[ -x $venv_python && -d $lib_dir ]] || return 1
  local files=()
  local name
  for name in "${backend_files[@]}"; do
    [[ -f $lib_dir/$name ]] && files+=("$lib_dir/$name")
  done
  (( ${#files[@]} > 0 )) || return 1
  "$venv_python" -m py_compile "${files[@]}"
}

sync_backend() {
  BACKEND_CHANGED=0
  [[ -n $source_root && -f $source_root/backend/server.py && -d $lib_dir ]] || return 1
  local name
  for name in "${backend_files[@]}"; do
    [[ -f $source_root/backend/$name ]] || continue
    if [[ ! -f $lib_dir/$name ]] \
        || ! cmp -s -- "$source_root/backend/$name" "$lib_dir/$name"; then
      install -m 644 -- "$source_root/backend/$name" "$lib_dir/$name"
      BACKEND_CHANGED=1
    fi
  done
  chmod 755 -- "$lib_dir/server.py"
  compile_backend || {
    echo "playback-runtime.sh: installed backend failed to compile" >&2
    return 2
  }
  return 0
}

wait_healthy() {
  local sock
  sock=$(socket_file)
  local i
  for i in $(seq 1 30); do
    if systemctl --user is-active --quiet "$unit" \
        && [[ -S $sock ]] \
        && "$venv_python" - "$sock" <<'PY'
import socket
import sys

path = sys.argv[1]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(2.0)
try:
    sock.connect(path)
    data = b""
    while b"\n" not in data and len(data) < 262144:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
finally:
    sock.close()
raise SystemExit(0 if b"\n" in data else 1)
PY
    then
      return 0
    fi
    sleep 0.2
  done
  echo "playback-runtime.sh: backend did not become healthy" >&2
  return 1
}

ensure_running() {
  local force_restart=${1:-0}
  BACKEND_CHANGED=0
  if [[ -n $source_root ]]; then
    sync_backend || return $?
  fi
  runtime_ready || {
    echo "playback-runtime.sh: YouTube Music playback is not installed yet" >&2
    return 1
  }
  if systemctl --user is-active --quiet "$unit"; then
    if (( force_restart == 1 || BACKEND_CHANGED == 1 )); then
      systemctl --user restart "$unit"
    fi
  else
    systemctl --user start "$unit"
  fi
  if wait_healthy; then
    return 0
  fi
  systemctl --user restart "$unit"
  wait_healthy
}

case $action in
  check)
    runtime_ready
    ;;
  start)
    ensure_running 0
    ;;
  stop)
    systemctl --user stop "$unit" 2>/dev/null || true
    ;;
  restart)
    ensure_running 1
    ;;
  health)
    runtime_ready || exit 1
    wait_healthy
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
