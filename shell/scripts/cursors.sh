#!/usr/bin/env bash
# Mouse cursors: list available themes and apply one to Umbriel and GTK.
set -uo pipefail

UMBRIEL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel"
CURSOR_PATH="$UMBRIEL_DIR/nbshell-cursor.toml"

themes() {
    local directory
    for directory in /usr/share/icons/*/cursors "$HOME"/.icons/*/cursors "$HOME"/.local/share/icons/*/cursors; do
        [ -d "$directory" ] || continue
        basename "$(dirname "$directory")"
    done | sort -u
}

cmd_list() {
    themes | python3 -c 'import json,sys; print(json.dumps([line.strip() for line in sys.stdin if line.strip()], ensure_ascii=False))'
}

cmd_current() {
    if [ -f "$CURSOR_PATH" ]; then
        python3 - "$CURSOR_PATH" <<'PY'
import json, pathlib, sys, tomllib
try:
    data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    cursor = data.get("input", {}).get("cursor", {})
    print(json.dumps({"theme": str(cursor.get("theme", "")), "size": int(cursor.get("size", 24))}))
except (OSError, ValueError, TypeError):
    print(json.dumps({"theme": "", "size": 24}))
PY
    else
        printf '{"theme":"%s","size":%s}\n' "${XCURSOR_THEME:-}" "${XCURSOR_SIZE:-24}"
    fi
}

cmd_apply() {
    local theme="${1:-}" size="${2:-24}"
    [ -n "$theme" ] || { echo "Theme is required" >&2; return 1; }
    themes | grep -qx "$theme" || {
        echo "Unknown cursor theme: $theme" >&2
        themes | sed 's/^/  /' >&2
        return 1
    }
    case "$size" in
        ''|*[!0-9]*) echo "Size must be a number: $size" >&2; return 1 ;;
    esac

    mkdir -p "$UMBRIEL_DIR"
    python3 - "$theme" "$size" "$CURSOR_PATH" <<'PY'
import json, pathlib, sys
theme, size, destination = sys.argv[1:]
text = "# Managed by nbshell cursor settings.\n[input.cursor]\n"
text += f"theme = {json.dumps(theme)}\nsize = {int(size)}\n"
path = pathlib.Path(destination)
temporary = path.with_suffix(".tmp")
temporary.write_text(text, encoding="utf-8")
temporary.replace(path)
PY

    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface cursor-theme "$theme" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null || true
    fi
    umbriel msg config-reload >/dev/null 2>&1 || true
    printf '%s %s\n' "$theme" "$size"
}

case "${1:-list}" in
    list) cmd_list ;;
    current) cmd_current ;;
    apply) shift; cmd_apply "$@" ;;
    *) echo "Usage: $(basename "$0") list|current|apply <theme> [size]" >&2; exit 2 ;;
esac
