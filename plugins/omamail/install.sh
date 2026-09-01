#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="omamail"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
plugin_home="$config_home/nbshell/plugins"
install_path="$plugin_home/$plugin_id"
backup_home="$config_home/nbshell/plugin-backups"
open_after=true

usage() { printf 'Usage: %s [--no-open]\n' "$0"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-open) open_after=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

command -v nbshell >/dev/null 2>&1 || {
  printf '%s\n' 'nbshell is required to install this plugin.' >&2
  exit 1
}

printf '%s\n' 'Validating Mail…'
nbshell plugin validate "$project_dir"
"$project_dir/scripts/migrate-storage.sh"

mkdir -p "$plugin_home"
if [[ -L "$install_path" && "$(readlink -f "$install_path")" == "$project_dir" ]]; then
  :
elif [[ -e "$install_path" || -L "$install_path" ]]; then
  mkdir -p "$backup_home"
  backup_path="$backup_home/$plugin_id.bak.$(date +%Y%m%d%H%M%S)"
  mv "$install_path" "$backup_path"
  printf 'Backed up the previous install to %s\n' "$backup_path"
  ln -s "$project_dir" "$install_path"
else
  ln -s "$project_dir" "$install_path"
fi

"$project_dir/scripts/install-mailto.sh" "$install_path"
if $open_after; then
  nbshell extension open "$plugin_id"
fi
printf 'Mail installed for development at %s\n' "$install_path"
