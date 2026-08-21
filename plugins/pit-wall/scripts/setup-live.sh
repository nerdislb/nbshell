#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
data_root=${XDG_DATA_HOME:-"$HOME/.local/share"}
runtime_root="$data_root/nbshell/pit-wall"
venv_dir="$runtime_root/venv"

command -v python3 >/dev/null 2>&1 || {
  echo "setup-live.sh: python3 is required" >&2
  exit 1
}

install -d -m 700 -- "$runtime_root"
if [[ ! -x $venv_dir/bin/python ]]; then
  python3 -m venv "$venv_dir"
fi
"$venv_dir/bin/pip" install --quiet --upgrade pip
"$venv_dir/bin/pip" install --quiet -r "$source_root/backend/requirements.txt"
"$venv_dir/bin/python" "$source_root/backend/live_bridge.py" --self-test

echo "Pit Wall live timing support installed in $runtime_root"
