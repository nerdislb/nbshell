#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/shell/scripts/plugins.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-plugin-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

for plugin in beispiel wetter headset omamail ytmusic pit-wall; do
    bash "$TOOL" validate "$ROOT/plugins/$plugin" >/dev/null
done

python3 - "$ROOT/shell/Catalog/plugins.json" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as handle:
    document = json.load(handle)
assert document.get("schemaVersion") == 1
plugins = document.get("plugins")
assert isinstance(plugins, list) and plugins
ids = [entry.get("id") for entry in plugins]
assert all(isinstance(ident, str) and ident for ident in ids)
assert len(ids) == len(set(ids)), "duplicate catalog id"
for entry in plugins:
    for field in ("name", "description", "author", "license", "category", "repository"):
        assert isinstance(entry.get(field), str) and entry[field], "%s misses %s" % (entry["id"], field)
    assert entry["source"] in ("bundled", "community")
    assert entry["repository"].startswith("https://")
    assert isinstance(entry.get("kinds"), list) and entry["kinds"]
    dependencies = entry.get("dependencies")
    assert isinstance(dependencies, dict)
    assert isinstance(dependencies.get("commands"), list)
    assert isinstance(dependencies.get("packages"), list)
PY

# Every function a bundled plugin calls on the shared Style singleton must be
# part of that compatibility API. QML resolves these calls lazily, so a typo
# may otherwise remain invisible until a rarely used control is hovered.
python3 - "$ROOT" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
style = (root / "shell/Commons/Style.qml").read_text(encoding="utf-8")
defined = set(re.findall(r"function\s+(\w+)\s*\(", style))
used = {}
for path in (root / "plugins").rglob("*.qml"):
    text = path.read_text(encoding="utf-8")
    for name in re.findall(r"\bStyle\.(\w+)\s*\(", text):
        used.setdefault(name, []).append(path.relative_to(root).as_posix())
missing = {name: paths for name, paths in used.items() if name not in defined}
assert not missing, "missing shared Style functions: %r" % missing
PY

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
make_fixture bad_dependencies '{"schemaVersion":2,"id":"bad-dependencies","name":"Bad","version":"1","kinds":["service"],"entryPoints":{"service":"Main.qml"},"dependencies":{"commands":"curl"}}'

must_reject traversal
must_reject absolute
must_reject wrong_schema
must_reject missing_kind
must_reject bad_dependencies

# Managed first-party modules can be disabled but never deleted by the plugin
# tool. External removal also cleans every config reference.
make_fixture managed '{"schemaVersion":2,"id":"test.managed","name":"Managed","version":"1","kinds":["service"],"entryPoints":{"service":"Main.qml"}}'
touch "$WORK/managed/.nbshell-managed"
XDG_CONFIG_HOME="$WORK/config" bash "$TOOL" add "$WORK/managed" managed >/dev/null
if XDG_CONFIG_HOME="$WORK/config" bash "$TOOL" remove managed >/dev/null 2>&1; then
    echo "ERROR: managed plugin was removable" >&2
    exit 1
fi

make_fixture removable '{"schemaVersion":2,"id":"test.removable","name":"Removable","version":"1","kinds":["bar-widget"],"entryPoints":{"barWidget":"Main.qml"}}'
XDG_CONFIG_HOME="$WORK/config" bash "$TOOL" add "$WORK/removable" removable >/dev/null
mkdir -p "$WORK/config/nbshell"
cat >"$WORK/config/nbshell/config.json" <<'JSON'
{
  "enabledPlugins": ["test.removable"],
  "rightWidgets": ["clock", "test.removable"],
  "pluginSettings": {"test.removable": {"example": true}}
}
JSON
XDG_CONFIG_HOME="$WORK/config" bash "$TOOL" remove removable >/dev/null
python3 - "$WORK/config/nbshell/config.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
assert "test.removable" not in data.get("enabledPlugins", [])
assert "test.removable" not in data.get("rightWidgets", [])
assert "test.removable" not in data.get("pluginSettings", {})
PY

echo "Plugin validation: OK"
