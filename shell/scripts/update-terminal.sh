#!/usr/bin/env bash
# Run one explicit update workflow, then keep its terminal available for review.
set -uo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-}"
channel="${2:-beta}"
case "$channel" in
    stable|beta) ;;
    *) echo 'Invalid update channel (expected stable or beta)' >&2; exit 2 ;;
esac

case "$mode" in
    shell|desktop|system|compositor|retry) ;;
    *) echo 'Invalid update workflow' >&2; exit 2 ;;
esac
args=("$mode" --channel "$channel")
# Preserve the explicit dashboard choice for the compositor confirmation.
[[ "$mode" == compositor || "$mode" == desktop ]] && args+=(--yes-compositor)
python3 "$script_dir/update-coordinator.py" "${args[@]}"
code=$?
printf '\nUpdate finished with exit code %s.\n' "$code"
if [[ -t 0 ]]; then
    read -r -n1 -p 'Press any key to close this window' || true
    printf '\n'
fi
exit "$code"
