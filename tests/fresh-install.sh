#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-install-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TEST_HOME="$WORK/home"
FAKE_BIN="$WORK/bin"
mkdir -p "$TEST_HOME" "$FAKE_BIN"

cat >"$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" is-active "*|*" is-enabled "*|*" cat "*) exit 1 ;;
    *) exit 0 ;;
esac
EOF

cat >"$FAKE_BIN/qs" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "list" ] && exit 0
exit 0
EOF

chmod +x "$FAKE_BIN/systemctl" "$FAKE_BIN/qs"

export HOME="$TEST_HOME"
export XDG_CONFIG_HOME="$TEST_HOME/.config"
export XDG_DATA_HOME="$TEST_HOME/.local/share"
export XDG_BIN_HOME="$TEST_HOME/.local/bin"
export PATH="$FAKE_BIN:/usr/bin:/bin"

"$ROOT/install.sh" >/dev/null

test -f "$XDG_CONFIG_HOME/quickshell/nbshell/shell.qml"
test "$(cat "$XDG_CONFIG_HOME/quickshell/nbshell/VERSION")" = "$(cat "$ROOT/VERSION")"
test -f "$XDG_CONFIG_HOME/nbshell/config.json"
test -f "$XDG_CONFIG_HOME/systemd/user/nbshell.service"
test -f "$XDG_CONFIG_HOME/niri/config.kdl"
test -f "$XDG_CONFIG_HOME/niri/nbshell-takeover.kdl"
test -f "$XDG_CONFIG_HOME/niri/nbshell-outputs.kdl"
test -x "$XDG_BIN_HOME/nbshell"
test -f "$XDG_DATA_HOME/applications/dev.nerdi.nbshell.desktop"
test "$(find "$XDG_CONFIG_HOME/nbshell/themes" -name colors.toml | wc -l)" -eq "$(find "$ROOT/themes" -name colors.toml | wc -l)"
test "$(find "$XDG_CONFIG_HOME/nbshell/plugins" -name manifest.json | wc -l)" -eq "$(find "$ROOT/plugins" -name manifest.json | wc -l)"

jq -e '
    .theme == "tokyo-night" and
    .mode == "bar" and
    .font == "JetBrainsMono Nerd Font" and
    .fontSize == 14 and
    .radius == 2 and
    .widgetStyle == "plain" and
    .enabledPlugins == []
' "$XDG_CONFIG_HOME/nbshell/config.json" >/dev/null

test "$("$XDG_BIN_HOME/nbshell" --version)" = "nbshell $(cat "$ROOT/VERSION")"

for harness in .agents .claude .codex; do
    test -L "$TEST_HOME/$harness/skills/nbshell"
done

# User configuration and custom plugins must survive an update.
jq '.testMarker = "keep"' "$XDG_CONFIG_HOME/nbshell/config.json" >"$WORK/config.json"
mv "$WORK/config.json" "$XDG_CONFIG_HOME/nbshell/config.json"
mkdir -p "$XDG_CONFIG_HOME/nbshell/plugins/custom"
printf '%s\n' keep >"$XDG_CONFIG_HOME/nbshell/plugins/custom/marker"

"$ROOT/install.sh" >/dev/null
jq -e '.testMarker == "keep"' "$XDG_CONFIG_HOME/nbshell/config.json" >/dev/null
test "$(cat "$XDG_CONFIG_HOME/nbshell/plugins/custom/marker")" = keep

# The package-free setup path must remain a valid equivalent entry point.
"$ROOT/setup.sh" --no-packages --yes >/dev/null
jq -e '.testMarker == "keep"' "$XDG_CONFIG_HOME/nbshell/config.json" >/dev/null

echo "Fresh install and update preservation: OK"
