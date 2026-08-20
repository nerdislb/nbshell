#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
section=right

usage() {
  cat <<'EOF'
Usage: scripts/install-local.sh [--section left|center|right]

Validate this checkout, install the user-level playback backend, link the
plugin into Omarchy, and enable the bar widget.
EOF
}

while (( $# > 0 )); do
  case $1 in
    --section)
      [[ $# -ge 2 ]] || { echo "install-local.sh: --section requires a value" >&2; exit 2; }
      section=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "install-local.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ $section =~ ^(left|center|right)$ ]] || {
  echo "install-local.sh: section must be left, center, or right" >&2
  exit 2
}

command -v omarchy >/dev/null 2>&1 || {
  echo "install-local.sh: Omarchy is required" >&2
  exit 1
}

omarchy plugin validate "$source_root"
"$source_root/scripts/setup.sh"

plugins_root="${XDG_CONFIG_HOME:-"$HOME/.config"}/omarchy/plugins"
target="$plugins_root/quickshell.ytmusic"
install -d -m 700 -- "$plugins_root"

if [[ -L $target && $(readlink -f -- "$target") == "$source_root" ]]; then
  echo "Local plugin link already points at this checkout."
elif [[ -e $target || -L $target ]]; then
  echo "install-local.sh: refusing to replace existing path: $target" >&2
  exit 1
else
  ln -s -- "$source_root" "$target"
  echo "Linked local plugin: $target -> $source_root"
fi

omarchy-shell shell rescanPlugins >/dev/null || true
discovered=0
for (( attempt = 0; attempt < 40; attempt++ )); do
  if omarchy plugin list --json | python3 -c 'import json,sys; data=json.load(sys.stdin); raise SystemExit(0 if any(item.get("id")=="quickshell.ytmusic" for item in data) else 1)'; then
    discovered=1
    break
  fi
  sleep 0.05
done
(( discovered )) || {
  echo "install-local.sh: Omarchy did not discover quickshell.ytmusic" >&2
  exit 1
}

omarchy plugin enable quickshell.ytmusic --section "$section"
echo "Installed. Click the YouTube Music bar widget to sign in and play."
