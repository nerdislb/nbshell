#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/shell/scripts/plugins.sh"
QMLFORMAT="$(command -v qmlformat || true)"
[ -n "$QMLFORMAT" ] || QMLFORMAT=/usr/lib/qt6/bin/qmlformat
[ -x "$QMLFORMAT" ] || { printf 'qmlformat is required for plugin smoke tests.\n' >&2; exit 1; }

for plugin in beispiel wetter headset hermarchy-agent omamail ytmusic pit-wall; do
    root="$ROOT/plugins/$plugin"
    bash "$TOOL" validate "$root" >/dev/null
    bash "$TOOL" design-check "$root" --strict >/dev/null
    while IFS= read -r -d '' qml; do
        "$QMLFORMAT" -n "$qml" >/dev/null
    done < <(find "$root" -type f -name '*.qml' -print0)
done

make -C "$ROOT/plugins/omamail" test
bash "$ROOT/plugins/ytmusic/scripts/test.sh"
node --test "$ROOT/plugins/pit-wall/tests/model.test.js"

printf 'Bundled plugin smoke tests: OK\n'
