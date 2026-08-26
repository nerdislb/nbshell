#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/shell/scripts/screensaver.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_fake() {
    local dir="$1" name="$2" version="$3"
    mkdir -p "$dir"
    printf '#!/usr/bin/env bash\n[ "${1:-}" = --version ] && printf "%%s\\n" "%s %s"\n' "$name" "$version" >"$dir/$name"
    chmod +x "$dir/$name"
}

mkdir -p "$TMP/empty"
[ "$(PATH="$TMP/empty:/usr/bin" bash "$SCRIPT" --renderer)" = "tte" ]

make_fake "$TMP/old" ttfx 0.3.1
[ "$(PATH="$TMP/old:/usr/bin" bash "$SCRIPT" --renderer)" = "tte" ]

make_fake "$TMP/current" ttfx 0.3.2
[ "$(PATH="$TMP/current:/usr/bin" bash "$SCRIPT" --renderer)" = "ttfx" ]

make_fake "$TMP/newer" ttfx 1.0.0
[ "$(PATH="$TMP/newer:/usr/bin" bash "$SCRIPT" --renderer)" = "ttfx" ]

echo "Screen-saver renderer selection: OK"
