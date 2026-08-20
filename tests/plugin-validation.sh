#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/shell/scripts/plugins.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-plugin-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

for plugin in beispiel wetter headset pit-wall; do
    bash "$TOOL" validate "$ROOT/plugins/$plugin" >/dev/null
done

make_fixture() {
    local name="$1" manifest="$2"
    mkdir -p "$WORK/$name"
    printf '%s\n' "$manifest" >"$WORK/$name/manifest.json"
    printf '%s\n' 'import QtQuick' 'Item {}' >"$WORK/$name/Main.qml"
}

must_reject() {
    local name="$1"
    if bash "$TOOL" validate "$WORK/$name" >/dev/null 2>&1; then
        echo "ERROR: unsafe manifest accepted: $name" >&2
        exit 1
    fi
}

make_fixture traversal '{"schemaVersion":2,"id":"bad-path","name":"Bad","version":"1","kinds":["panel"],"entryPoints":{"panel":"../Main.qml"}}'
make_fixture absolute '{"schemaVersion":2,"id":"bad-absolute","name":"Bad","version":"1","kinds":["service"],"entryPoints":{"service":"/tmp/Main.qml"}}'
make_fixture wrong_schema '{"schemaVersion":1,"id":"omarchy-only","name":"Bad","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
make_fixture missing_kind '{"schemaVersion":2,"id":"missing-kind","name":"Bad","version":"1","kinds":["overlay"],"entryPoints":{"service":"Main.qml"}}'

must_reject traversal
must_reject absolute
must_reject wrong_schema
must_reject missing_kind

echo "Plugin validation: OK"
