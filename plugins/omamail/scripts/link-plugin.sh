#!/usr/bin/env bash
# This bundled snapshot targets nbshell, not the upstream Omarchy shell.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ${1:-} == --no-restart ]]; then shift; set -- --no-open "$@"; fi
exec "$project_dir/install.sh" "$@"
