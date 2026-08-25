#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
  cat <<'EOF'
Usage: scripts/setup.sh

Install the unprivileged YouTube Music playback backend: a user venv with
ytmusicapi, a copy of the backend outside the plugin tree, and a static
systemd user unit that is never enabled at login.
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi

for command_name in python3 mpv yt-dlp systemctl install; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "setup.sh: required command is missing: $command_name" >&2
    echo "Install mpv and yt-dlp with: sudo pacman -S mpv yt-dlp" >&2
    exit 1
  }
done

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
data_root=${XDG_DATA_HOME:-"$HOME/.local/share"}
lib_dir="$HOME/.local/lib/omarchy-ytmusic"
venv_dir="$data_root/omarchy-ytmusic/venv"
unit_dir="$config_root/systemd/user"
unit_file="$unit_dir/omarchy-ytmusic.service"
auth_dir="$config_root/omarchy-ytmusic"

# Never compile or write inside the plugin directory. nbshell reloads plugin
# files and keeps the user-owned runtime separate from its source.
install -d -m 700 -- "$lib_dir" "$auth_dir" "$unit_dir" "$(dirname -- "$venv_dir")"

install -m 644 -- \
  "$source_root/backend/server.py" \
  "$source_root/backend/protocol.py" \
  "$source_root/backend/auth.py" \
  "$source_root/backend/catalog.py" \
  "$source_root/backend/player.py" \
  "$source_root/backend/play_history.py" \
  "$lib_dir/"
chmod 755 -- "$lib_dir/server.py"

if [[ ! -x $venv_dir/bin/python ]]; then
  python3 -m venv "$venv_dir"
fi
"$venv_dir/bin/pip" install --upgrade pip >/dev/null
"$venv_dir/bin/pip" install -r "$source_root/backend/requirements.txt"

# Point the unit at the installed copy. The plugin directory is only a source.
sed "s|ExecStart=.*|ExecStart=$venv_dir/bin/python $lib_dir/server.py|" \
  "$source_root/systemd/omarchy-ytmusic.service" > "$unit_file"
chmod 644 -- "$unit_file"

systemctl --user daemon-reload

# Import an existing ytmusicbar session if this install has none yet.
if [[ ! -s $auth_dir/browser.json && -s $config_root/ytmusicbar/browser.json ]]; then
  install -m 600 -- "$config_root/ytmusicbar/browser.json" "$auth_dir/browser.json"
fi

"$venv_dir/bin/python" "$lib_dir/server.py" --self-test >/dev/null

echo "Installed YouTube Music playback to $lib_dir"
echo "The user unit is $unit_file and is not enabled at login."
