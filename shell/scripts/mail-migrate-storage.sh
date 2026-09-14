#!/usr/bin/env bash
# Preserve existing Mail state; rename legacy state only when no target exists.
set -euo pipefail
move_once() {
    local old=$1 new=$2
    if [[ -d "$old" && ! -L "$old" && ! -e "$new" && ! -L "$new" ]]; then
        mv -T -- "$old" "$new"
    fi
}
move_once "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-gmail" "${XDG_CONFIG_HOME:-$HOME/.config}/omamail"
move_once "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-gmail" "${XDG_CACHE_HOME:-$HOME/.cache}/omamail"
