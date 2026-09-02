#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
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
# signalrcore 1.0.2 hard-pins msgpack 1.1.2, which is affected by
# CVE-2026-57585. Its JSON protocol is compatible with the patched 1.2 line,
# so let nbshell's requirements select the safe msgpack release first, then
# install the reviewed client without its stale dependency declaration.
"$venv_dir/bin/pip" uninstall --quiet --yes signalrcore >/dev/null 2>&1 || true
"$venv_dir/bin/pip" install --quiet -r "$source_root/backend/requirements.txt"
"$venv_dir/bin/pip" install --quiet --no-deps 'signalrcore==1.0.2'
"$venv_dir/bin/python" "$source_root/backend/live_bridge.py" --self-test

echo "Pit Wall live timing support installed in $runtime_root"
