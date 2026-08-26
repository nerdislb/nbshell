#!/usr/bin/env bash
# Optional systemd-oomd policy for runaway graphical applications.
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DROPIN_DIR="$CONFIG_HOME/systemd/user/app.slice.d"
DROPIN="$DROPIN_DIR/90-nbshell-memory-guard.conf"

user_property() {
    systemctl --user show "$1" --property="$2" --value 2>/dev/null || true
}

enable_oomd() {
    if [ "$(id -u)" -eq 0 ]; then
        systemctl enable --now systemd-oomd.service
    elif sudo -n true 2>/dev/null; then
        sudo -n systemctl enable --now systemd-oomd.service
    elif command -v pkexec >/dev/null 2>&1; then
        pkexec /usr/bin/systemctl enable --now systemd-oomd.service
    else
        echo "Enabling systemd-oomd requires administrator authentication." >&2
        return 1
    fi
}

status() {
    local format="${1:-}"
    local configured=false oomd shell_slice pressure limit duration swap protected=false
    [ -f "$DROPIN" ] && configured=true
    oomd="$(systemctl is-active systemd-oomd.service 2>/dev/null || true)"
    [ -n "$oomd" ] || oomd=unavailable
    shell_slice="$(user_property nbshell.service Slice)"
    pressure="$(user_property app.slice ManagedOOMMemoryPressure)"
    limit="$(user_property app.slice ManagedOOMMemoryPressureLimit)"
    duration="$(user_property app.slice ManagedOOMMemoryPressureDurationUSec)"
    swap="$(user_property app.slice ManagedOOMSwap)"
    # systemd exposes the percentage as a 32-bit fixed-point integer.
    if [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -gt 100 ]; then
        limit="$(awk -v value="$limit" 'BEGIN { printf "%.0f%%", value / 4294967295 * 100 }')"
    fi
    if [ "$configured" = true ] && [ "$oomd" = active ] && \
       [ "$shell_slice" = session.slice ] && [ "$pressure" = kill ] && \
       [ "$swap" = kill ]; then
        protected=true
    fi

    if [ "$format" = "--json" ]; then
        python3 - "$configured" "$oomd" "$shell_slice" "$pressure" "$limit" "$duration" "$swap" "$protected" <<'PY'
import json, sys
configured, oomd, shell_slice, pressure, limit, duration, swap, protected = sys.argv[1:]
print(json.dumps({
    "configured": configured == "true",
    "oomd": oomd,
    "shellSlice": shell_slice or "unknown",
    "appPressure": pressure or "unknown",
    "appPressureLimit": limit or "unknown",
    "appPressureDuration": duration or "unknown",
    "appSwap": swap or "unknown",
    "protected": protected == "true",
}))
PY
        return
    fi

    printf 'Memory guard  %s\n' "$([ "$protected" = true ] && echo protected || echo disabled)"
    printf 'systemd-oomd  %s\n' "$oomd"
    printf 'nbshell slice %s\n' "${shell_slice:-unknown}"
    printf 'app pressure  %s (limit %s, duration %s)\n' "${pressure:-unknown}" "${limit:-unknown}" "${duration:-unknown}"
    printf 'swap policy   %s\n' "${swap:-unknown}"
}

setup() {
    mkdir -p "$DROPIN_DIR"
    local temporary="$DROPIN.tmp.$$"
    trap 'rm -f "$temporary"' EXIT
    printf '%s\n' \
        '[Slice]' \
        'ManagedOOMMemoryPressure=kill' \
        'ManagedOOMMemoryPressureLimit=60%' \
        'ManagedOOMMemoryPressureDurationSec=20s' \
        'ManagedOOMSwap=kill' >"$temporary"
    chmod 0644 "$temporary"
    mv "$temporary" "$DROPIN"
    trap - EXIT

    systemctl --user daemon-reload
    systemctl --user set-property --runtime app.slice \
        ManagedOOMMemoryPressure=kill \
        ManagedOOMMemoryPressureLimit=60% \
        ManagedOOMMemoryPressureDurationSec=20s \
        ManagedOOMSwap=kill
    enable_oomd
    systemctl --user try-restart nbshell-umbriel-resume-guard.service
    systemctl --user try-restart nbshell.service
    status
}

remove() {
    rm -f "$DROPIN"
    rmdir "$DROPIN_DIR" 2>/dev/null || true
    systemctl --user daemon-reload
    # Do not disable systemd-oomd: another desktop component may use it.
    systemctl --user set-property --runtime app.slice \
        ManagedOOMMemoryPressure=auto ManagedOOMSwap=auto
    status
}

case "${1:-status}" in
    status) status "${2:-}" ;;
    setup) setup ;;
    remove) remove ;;
    *) echo "Usage: nbshell memory-guard [status [--json]|setup|remove]" >&2; exit 2 ;;
esac
