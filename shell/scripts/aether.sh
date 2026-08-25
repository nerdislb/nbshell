#!/usr/bin/env bash
set -euo pipefail

command_name=${1:-status}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
runtime_shell="$config_home/quickshell/nbshell"
hook_dir="$config_home/aether/custom/nbshell"
source_theme="$config_home/aether/theme"
state_dir="$state_home/nbshell"
theme_name=aether-current

install_hook() {
    command -v aether >/dev/null 2>&1 || {
        echo "Aether is not installed; the nbshell hook was not added." >&2
        exit 1
    }
    local source="$runtime_shell/integrations/aether/custom"
    [ -f "$source/config.json" ] || {
        echo "The bundled Aether hook is missing. Reinstall nbshell first." >&2
        exit 1
    }
    install -d "$hook_dir" "$state_dir"
    install -m 644 "$source/config.json" "$hook_dir/config.json"
    install -m 644 "$source/nbshell.palette" "$hook_dir/nbshell.palette"
    install -m 755 "$source/post-apply.sh" "$hook_dir/post-apply.sh"
    echo "Aether Apply now updates nbshell automatically."
}

apply_theme() (
    install -d "$state_dir"
    exec 9>"$state_dir/aether-apply.lock"
    flock -n 9 || exit 0

    [ -f "$source_theme/colors.toml" ] || {
        echo "Aether has not generated a theme yet." >&2
        exit 1
    }

    local stage
    stage=$(mktemp -d "${TMPDIR:-/tmp}/nbshell-aether.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    install -d "$stage/$theme_name"
    install -m 644 "$source_theme/colors.toml" "$stage/$theme_name/colors.toml"
    if [ -d "$source_theme/backgrounds" ]; then
        cp -a "$source_theme/backgrounds" "$stage/$theme_name/backgrounds"
    fi

    "$HOME/.local/bin/nbshell" theme install --force "$stage/$theme_name" >/dev/null
    # The IPC reload acknowledges before the asynchronous QML model has
    # necessarily finished scanning the new directory. Wait for that model so
    # the following set cannot be discarded as an unknown theme.
    local attempt ready=0
    for attempt in $(seq 1 30); do
        if "$HOME/.local/bin/nbshell" theme list 2>/dev/null \
                | awk '{print $1}' | grep -Fxq "$theme_name"; then
            ready=1
            break
        fi
        sleep 0.1
    done
    [ "$ready" -eq 1 ] || {
        echo "nbshell did not discover '$theme_name' after import." >&2
        exit 1
    }
    "$HOME/.local/bin/nbshell" theme "$theme_name" >/dev/null
    ready=0
    for attempt in $(seq 1 30); do
        if [ "$("$HOME/.local/bin/nbshell" theme current 2>/dev/null)" = "$theme_name" ]; then
            ready=1
            break
        fi
        sleep 0.1
    done
    [ "$ready" -eq 1 ] || {
        echo "nbshell did not activate '$theme_name'." >&2
        exit 1
    }
    command -v notify-send >/dev/null 2>&1 \
        && notify-send -a nbshell "Theme applied" "Aether updated nbshell." \
        || true
    echo "Aether theme imported and activated as '$theme_name'."
)

status() {
    printf 'hook=%s\n' "$([ -x "$hook_dir/post-apply.sh" ] && echo installed || echo missing)"
    printf 'source=%s\n' "$([ -f "$source_theme/colors.toml" ] && echo ready || echo missing)"
    printf 'theme=%s\n' "$theme_name"
}

case "$command_name" in
    setup|install-hook) install_hook ;;
    apply|import) apply_theme ;;
    status) status ;;
    *) echo "Usage: nbshell aether setup|apply|status" >&2; exit 2 ;;
esac
