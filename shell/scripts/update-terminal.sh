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
    shell) python3 "$script_dir/nbshell-update.py" install --channel "$channel"; code=$? ;;
    compositor) python3 "$script_dir/umbriel-update.py" install --yes; code=$? ;;
    desktop)
        python3 "$script_dir/nbshell-update.py" install --channel "$channel" &&
            python3 "$script_dir/umbriel-update.py" install --yes
        code=$?
        ;;
    system) bash "$script_dir/updates.sh" run; code=$? ;;
    *) echo 'Invalid update workflow' >&2; exit 2 ;;
esac
printf '\nUpdate finished with exit code %s.\n' "$code"
if [[ -t 0 ]]; then
    read -r -n1 -p 'Press any key to close this window' || true
    printf '\n'
fi
exit "$code"
