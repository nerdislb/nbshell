#!/usr/bin/env bash
set -euo pipefail

purge=0
if [[ ${1:-} == --purge ]]; then
  purge=1
elif [[ -n ${1:-} ]]; then
  echo "Usage: scripts/remove-runtime.sh [--purge]" >&2
  exit 2
fi

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
data_root=${XDG_DATA_HOME:-"$HOME/.local/share"}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}
runtime_root=${XDG_RUNTIME_DIR:-/tmp}

systemctl --user stop omarchy-ytmusic.service 2>/dev/null || true
rm -f -- "$config_root/systemd/user/omarchy-ytmusic.service"
systemctl --user daemon-reload 2>/dev/null || true

rm -rf -- "$HOME/.local/lib/omarchy-ytmusic"
rm -f -- "$runtime_root/omarchy-ytmusic/backend.sock" \
  "$runtime_root/omarchy-ytmusic/mpv.sock"

if (( purge )); then
  rm -rf -- \
    "$data_root/omarchy-ytmusic" \
    "$config_root/omarchy-ytmusic" \
    "$cache_root/omarchy-ytmusic" \
    "$runtime_root/omarchy-ytmusic"
fi

echo "Removed the YouTube Music playback unit and installed backend."
if (( purge )); then
  echo "Purged venv, auth file, and cache."
fi
