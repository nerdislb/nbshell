#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/shell/scripts/plugins.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-plugin-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

python3 -m unittest "$ROOT/tests/test_plugin_porting_lab.py"

for plugin in beispiel wetter headset buds-control hermarchy-agent omamail ytmusic pit-wall; do
    bash "$TOOL" validate "$ROOT/plugins/$plugin" >/dev/null
    bash "$TOOL" design-check "$ROOT/plugins/$plugin" --strict >/dev/null
done

QMLFORMAT="${QMLFORMAT_BIN:-/usr/lib/qt6/bin/qmlformat}"
if [ -x "$QMLFORMAT" ]; then
    while IFS= read -r -d '' qml; do
        "$QMLFORMAT" -n "$qml" >/dev/null
    done < <(find "$ROOT/plugins" -type f -name '*.qml' -print0)
fi

# signalrcore 1.0.2 still declares vulnerable msgpack 1.1.2. Pit Wall must
# install the reviewed client without that stale transitive pin and select the
# patched msgpack line explicitly.
grep -Fxq 'msgpack>=1.2.1,<2' "$ROOT/plugins/pit-wall/backend/requirements.txt"
grep -Fq 'pip" install --quiet --no-deps '\''signalrcore==1.0.2'\''' "$ROOT/plugins/pit-wall/scripts/setup-live.sh"

python3 - "$ROOT/shell/Catalog/plugins.json" "$ROOT/plugins" <<'PY'
import json, pathlib, sys

with open(sys.argv[1], encoding="utf-8") as handle:
    document = json.load(handle)
plugin_root = pathlib.Path(sys.argv[2])
assert document.get("schemaVersion") == 1
plugins = document.get("plugins")
assert isinstance(plugins, list) and plugins
bundled = {}
for manifest_path in plugin_root.glob("*/manifest.json"):
    with manifest_path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    ident = manifest.get("id")
    assert ident not in bundled, "duplicate bundled plugin id: %s" % ident
    bundled[ident] = manifest
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
    if entry["source"] == "bundled":
        assert entry["id"] in bundled, "missing bundled manifest: %s" % entry["id"]
        manifest = bundled[entry["id"]]
        for field in ("id", "name", "description", "author", "license", "category", "repository", "kinds", "dependencies"):
            assert entry.get(field) == manifest.get(field), "%s catalog drift: %s" % (entry["id"], field)
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

# Plugin references to the core icon singleton are also resolved lazily. Keep
# every bundled plugin on names that the installed Icons API actually exports.
python3 - "$ROOT" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
icons = (root / "shell/Common/Icons.qml").read_text(encoding="utf-8")
defined = set(re.findall(r"readonly\s+property\s+\w+\s+(\w+)\s*:", icons))
used = {}
for path in (root / "plugins").rglob("*.qml"):
    text = path.read_text(encoding="utf-8")
    for name in re.findall(r"\bIcons\.(\w+)\b", text):
        used.setdefault(name, []).append(path.relative_to(root).as_posix())
missing = {name: paths for name, paths in used.items() if name not in defined}
assert not missing, "missing shared Icons properties: %r" % missing
PY

make_fixture() {
    local name="$1" manifest="$2"
    mkdir -p "$WORK/$name"
    printf '%s\n' "$manifest" >"$WORK/$name/manifest.json"
    printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {}' >"$WORK/$name/Main.qml"
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
make_fixture bad_hosts '{"schemaVersion":2,"id":"bad-hosts","name":"Bad","version":"1","kinds":["service"],"entryPoints":{"service":"Main.qml"},"hosts":["root-shell"]}'

must_reject traversal
must_reject absolute
must_reject wrong_schema
must_reject missing_kind
must_reject bad_dependencies
must_reject bad_hosts

make_fixture adaptive '{"schemaVersion":2,"id":"test.adaptive","name":"Adaptive","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"},"hosts":["panel","window"]}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' \
    'Item {' '  function open(payloadJson) {}' '  function close() {}' \
    '  Keys.onEscapePressed: close()' '}' >"$WORK/adaptive/Main.qml"
XDG_CONFIG_HOME="$WORK/adaptive-config" bash "$TOOL" add "$WORK/adaptive" adaptive >/dev/null
XDG_CONFIG_HOME="$WORK/adaptive-config" bash "$TOOL" list | python3 -c 'import json,sys; assert json.load(sys.stdin)[0]["hosts"] == ["panel", "window"]'

make_fixture adaptive_duplicate '{"schemaVersion":2,"id":"test.adaptive","name":"Duplicate","version":"1","kinds":["service"],"entryPoints":{"service":"Main.qml"}}'
if XDG_CONFIG_HOME="$WORK/adaptive-config" bash "$TOOL" add "$WORK/adaptive_duplicate" duplicate >/dev/null 2>&1; then
    echo "ERROR: plugin add accepted a duplicate manifest ID" >&2
    exit 1
fi

# The golden-path generator emits every supported plugin kind as a structurally
# valid, strict design-contract-clean directory with no unresolved placeholders.
for kind in bar-widget panel overlay service; do
    target="$WORK/generated-$kind"
    bash "$TOOL" new "io.github.test.$kind" --kind "$kind" --output "$target" --author Test >/dev/null
    bash "$TOOL" validate "$target" >/dev/null
    bash "$TOOL" design-check "$target" --strict >/dev/null
    if command -v qmlformat >/dev/null 2>&1; then
        for qml in "$target"/*.qml; do qmlformat -n "$qml" >/dev/null; done
    fi
    test "$(stat -c %d "$target")" = "$(stat -c %d "$(dirname "$target")")"
    if grep -R '{{[A-Z]*}}' "$target" >/dev/null 2>&1; then
        echo "ERROR: unresolved scaffold marker in $kind" >&2
        exit 1
    fi
done
special="$WORK/generated-special"
bash "$TOOL" new "io.github.test.special" --kind panel --output "$special" \
    --name 'Quoted "plugin"' --author 'Test "Author"' >/dev/null
bash "$TOOL" validate "$special" >/dev/null
python3 - "$special/manifest.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
assert manifest["name"] == 'Quoted "plugin"'
assert manifest["author"] == 'Test "Author"'
PY
if bash "$TOOL" new 'nbshell.reserved' --output "$WORK/reserved" >/dev/null 2>&1; then
    echo "ERROR: scaffold accepted the reserved namespace" >&2
    exit 1
fi
if bash "$TOOL" new 'test.invalid/kind' --output "$WORK/invalid" >/dev/null 2>&1; then
    echo "ERROR: scaffold accepted an invalid plugin id" >&2
    exit 1
fi

# Design findings are advisory by default and enforceable with --strict. A
# narrow suppression marker keeps intentional, specialist rendering possible.
make_fixture design_bad '{"schemaVersion":2,"id":"test.design-bad","name":"Design bad","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' \
    'import QtQuick' \
    'Item {' \
    '  function open(payloadJson) {}' \
    '  function close() {}' \
    '  Rectangle { color: "#ff00ff"; radius: 7 }' \
    '  Rectangle { color: Qt.rgba(1, 0, 1, 1) }' \
    '  NumberAnimation { duration: 175 }' \
    '}' >"$WORK/design_bad/Main.qml"
bash "$TOOL" design-check "$WORK/design_bad" >/dev/null
if bash "$TOOL" design-check "$WORK/design_bad" --strict >/dev/null 2>&1; then
    echo "ERROR: strict design check accepted private UI literals and missing contracts" >&2
    exit 1
fi
if XDG_CONFIG_HOME="$WORK/design-add-config" bash "$TOOL" add "$WORK/design_bad" design-bad >/dev/null 2>&1; then
    echo "ERROR: plugin add bypassed the strict design contract" >&2
    exit 1
fi

make_fixture design_comments '{"schemaVersion":2,"id":"test.design-comments","name":"Design comments","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' \
    'import QtQuick' \
    'import qs.Common' \
    'import qs.Widgets' \
    'Item {' \
    '  // function open(payloadJson) {}' \
    '  // function close() {}' \
    '  // Keys.onEscapePressed: {}' \
    '  readonly property color privateRed: "red"' \
    '}' >"$WORK/design_comments/Main.qml"
if bash "$TOOL" design-check "$WORK/design_comments" --strict >/dev/null 2>&1; then
    echo "ERROR: comments bypassed lifecycle checks or a private named color" >&2
    exit 1
fi

make_fixture design_clean_comments '{"schemaVersion":2,"id":"test.design-clean-comments","name":"Design clean comments","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' \
    'import QtQuick' \
    'import qs.Common' \
    'import qs.Widgets' \
    'Item {' \
    '  // Example only: color: "#ff00ff" and duration: 175' \
    '  function open(payloadJson) {}' \
    '  function close() {}' \
    '  Keys.onEscapePressed: {}' \
    '}' >"$WORK/design_clean_comments/Main.qml"
bash "$TOOL" design-check "$WORK/design_clean_comments" --strict >/dev/null

make_fixture design_semantic_derivation '{"schemaVersion":2,"id":"test.design-semantic-derivation","name":"Design semantic derivation","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property color source: Theme.fg' \
    '  property color clear: "transparent"' \
    '  property color muted: Qt.rgba(source.r, source.g, source.b, 0.6)' \
    '  property real spacing: 0' '}' \
    >"$WORK/design_semantic_derivation/Main.qml"
mkdir -p "$WORK/design_semantic_derivation/tests"
printf '%s\n' 'import QtQuick' 'Item { property color fixture: "#ff00ff" }' \
    >"$WORK/design_semantic_derivation/tests/Fixture.qml"
bash "$TOOL" design-check "$WORK/design_semantic_derivation" --strict >/dev/null

make_fixture design_hex '{"schemaVersion":2,"id":"test.design-hex","name":"Design hex","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property color privateHex: "#ff00ff"' '}' >"$WORK/design_hex/Main.qml"
if bash "$TOOL" design-check "$WORK/design_hex" --strict >/dev/null 2>&1; then
    echo "ERROR: strict design check accepted a quoted hex color" >&2
    exit 1
fi

make_fixture design_named_color '{"schemaVersion":2,"id":"test.design-named-color","name":"Design named color","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property color privateOrange: "orange"' '}' >"$WORK/design_named_color/Main.qml"
if bash "$TOOL" design-check "$WORK/design_named_color" --strict >/dev/null 2>&1; then
    echo "ERROR: strict design check accepted an arbitrary named color" >&2
    exit 1
fi

make_fixture design_string_sample '{"schemaVersion":2,"id":"test.design-string-sample","name":"Design string sample","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property string sample: "color: Qt.rgba(1, 0, 1, 1)"' '}' >"$WORK/design_string_sample/Main.qml"
bash "$TOOL" design-check "$WORK/design_string_sample" --strict >/dev/null

make_fixture design_fake_suppression '{"schemaVersion":2,"id":"test.design-fake-suppression","name":"Design fake suppression","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property string sample: "nbshell-design: allow-hardcoded-color"; property color bad: Qt.rgba(1, 0, 1, 1)' '}' >"$WORK/design_fake_suppression/Main.qml"
if bash "$TOOL" design-check "$WORK/design_fake_suppression" --strict >/dev/null 2>&1; then
    echo "ERROR: a suppression marker inside a string bypassed a real color finding" >&2
    exit 1
fi

make_fixture design_real_suppression '{"schemaVersion":2,"id":"test.design-real-suppression","name":"Design real suppression","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property color intentional: Qt.rgba(1, 0, 1, 1) // nbshell-design: allow-hardcoded-color' '}' >"$WORK/design_real_suppression/Main.qml"
bash "$TOOL" design-check "$WORK/design_real_suppression" --strict >/dev/null

make_fixture design_template_string '{"schemaVersion":2,"id":"test.design-template-string","name":"Design template string","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property string sample: `color: Qt.rgba(1, 0, 1, 1)`' '}' >"$WORK/design_template_string/Main.qml"
bash "$TOOL" design-check "$WORK/design_template_string" --strict >/dev/null

make_fixture design_template_suppression '{"schemaVersion":2,"id":"test.design-template-suppression","name":"Design template suppression","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property string sample: `// nbshell-design: allow-hardcoded-color`; property color bad: Qt.rgba(1, 0, 1, 1)' '}' >"$WORK/design_template_suppression/Main.qml"
if bash "$TOOL" design-check "$WORK/design_template_suppression" --strict >/dev/null 2>&1; then
    echo "ERROR: a backtick suppression string bypassed a real color finding" >&2
    exit 1
fi

for value in '"orange"' 'Qt.rgba(1, 0, 1, 1)' 'Qt.hsla(0.8, 1, 0.5, 1)' 'Qt.hsva(0.8, 1, 1, 1)'; do
    make_fixture design_multiline '{"schemaVersion":2,"id":"test.design-multiline","name":"Design multiline","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
    printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
        '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
        '  property color bad:' "    $value" '}' >"$WORK/design_multiline/Main.qml"
    if bash "$TOOL" design-check "$WORK/design_multiline" --strict >/dev/null 2>&1; then
        echo "ERROR: strict design check accepted multiline color value: $value" >&2
        exit 1
    fi
    rm -rf "$WORK/design_multiline"
done

for value in '("#ff00ff")' 'true ? "#ff00ff" : Theme.fg' 'Qt.lighter(Qt.rgba(1, 0, 1, 1))'; do
    make_fixture design_expression '{"schemaVersion":2,"id":"test.design-expression","name":"Design expression","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
    printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
        '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
        "  property color bad: $value" '}' >"$WORK/design_expression/Main.qml"
    if bash "$TOOL" design-check "$WORK/design_expression" --strict >/dev/null 2>&1; then
        echo "ERROR: strict design check accepted wrapped color expression: $value" >&2
        exit 1
    fi
    rm -rf "$WORK/design_expression"
done

make_fixture design_regex_sample '{"schemaVersion":2,"id":"test.design-regex-sample","name":"Design regex sample","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  function open(payloadJson) {}' '  function close() {}' '  Keys.onEscapePressed: {}' \
    '  property var pattern: /color: "#ff00ff"/' '}' >"$WORK/design_regex_sample/Main.qml"
bash "$TOOL" design-check "$WORK/design_regex_sample" --strict >/dev/null

make_fixture design_nested_lifecycle '{"schemaVersion":2,"id":"test.design-nested-lifecycle","name":"Design nested lifecycle","version":"1","kinds":["panel"],"entryPoints":{"panel":"Main.qml"}}'
printf '%s\n' 'import QtQuick' 'import qs.Common' 'import qs.Widgets' 'Item {' \
    '  Item {' '    function open(payloadJson) {}' '    function close() {}' \
    '    Keys.onEscapePressed: {}' '  }' '}' >"$WORK/design_nested_lifecycle/Main.qml"
if bash "$TOOL" design-check "$WORK/design_nested_lifecycle" --strict >/dev/null 2>&1; then
    echo "ERROR: child lifecycle methods satisfied the entry-point root contract" >&2
    exit 1
fi

printf '%s\n' 'import QtQuick' 'Item {}' >"$WORK/outside.qml"
make_fixture design_traversal '{"schemaVersion":2,"id":"test.design-traversal","name":"Design traversal","version":"1","kinds":["panel"],"entryPoints":{"panel":"../outside.qml"}}'
if bash "$TOOL" design-check "$WORK/design_traversal" --strict >/dev/null 2>&1; then
    echo "ERROR: design check followed an entry point outside the plugin" >&2
    exit 1
fi

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
test ! -e "$WORK/config/nbshell/plugins/removable/.git"
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

# Git-managed plugins run unsandboxed. A fetch may discover new code, but a
# non-interactive update must not merge it without an explicit --yes.
update_upstream="$WORK/update-upstream"
git init --quiet --initial-branch=main "$update_upstream"
printf '%s\n' '{"schemaVersion":2,"id":"test.updateme","name":"Updateme","version":"1","kinds":["service"],"entryPoints":{"service":"Main.qml"}}' \
    >"$update_upstream/manifest.json"
printf '%s\n' 'import QtQuick' 'Item {}' >"$update_upstream/Main.qml"
git -C "$update_upstream" -c user.email=test@example.com -c user.name=Test add -A
git -C "$update_upstream" -c user.email=test@example.com -c user.name=Test commit --quiet -m initial

XDG_CONFIG_HOME="$WORK/update-config" bash "$TOOL" add "file://$update_upstream" updateme >/dev/null
update_clone="$WORK/update-config/nbshell/plugins/updateme"
update_before="$(git -C "$update_clone" rev-parse HEAD)"

printf '%s\n' 'import QtQuick' 'Item { property bool changed: true }' >"$update_upstream/Main.qml"
git -C "$update_upstream" -c user.email=test@example.com -c user.name=Test commit --quiet -am "new commit"
update_upstream_head="$(git -C "$update_upstream" rev-parse HEAD)"

update_output="$(XDG_CONFIG_HOME="$WORK/update-config" bash "$TOOL" update updateme </dev/null 2>&1)"
test "$(git -C "$update_clone" rev-parse HEAD)" = "$update_before"
grep -q "Skipped 'updateme'" <<<"$update_output"
test -z "$(git -C "$update_clone" status --porcelain)"

XDG_CONFIG_HOME="$WORK/update-config" bash "$TOOL" update updateme --yes >/dev/null
test "$(git -C "$update_clone" rev-parse HEAD)" = "$update_upstream_head"

# Repository-local hooks must never execute during managed updates either.
hook_marker="$WORK/plugin-hook-ran"
mkdir -p "$update_clone/.git/hooks"
printf '%s\n' '#!/bin/sh' "touch '$hook_marker'" >"$update_clone/.git/hooks/post-merge"
chmod +x "$update_clone/.git/hooks/post-merge"
printf '%s\n' 'import QtQuick' 'Item { property bool changedAgain: true }' >"$update_upstream/Main.qml"
git -C "$update_upstream" -c user.email=test@example.com -c user.name=Test commit --quiet -am "another safe commit"
XDG_CONFIG_HOME="$WORK/update-config" bash "$TOOL" update updateme --yes >/dev/null
test ! -e "$hook_marker"

printf '%s\n' 'import QtQuick' 'Item { property color unsafeColor: "#ff00ff" }' >"$update_upstream/Main.qml"
git -C "$update_upstream" -c user.email=test@example.com -c user.name=Test commit --quiet -am "unsafe design"
safe_head="$(git -C "$update_clone" rev-parse HEAD)"
unsafe_output="$(XDG_CONFIG_HOME="$WORK/update-config" bash "$TOOL" update updateme --yes 2>&1)"
test "$(git -C "$update_clone" rev-parse HEAD)" = "$safe_head"
grep -q "strict design contract failed" <<<"$unsafe_output"

echo "Plugin validation: OK"
