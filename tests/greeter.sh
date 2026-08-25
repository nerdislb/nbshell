#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/setup-greeter.sh"
niri validate -c "$ROOT/greeter/niri.kdl" >/dev/null
python3 -m py_compile "$ROOT/shell/scripts/greeter-theme.py"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
test_config="$stage/user-config"
mkdir -p "$test_config/nbshell/themes/test/backgrounds"
cp "$ROOT/themes/tokyo-night/colors.toml" "$test_config/nbshell/themes/test/colors.toml"
touch "$test_config/nbshell/themes/test/backgrounds/test.jpg"
printf '{"theme":"test","radius":7,"font":"Test Font"}\n' > "$test_config/nbshell/config.json"
XDG_CONFIG_HOME="$test_config" python3 "$ROOT/shell/scripts/greeter-theme.py" "$stage/out" >/dev/null
grep -Fq 'border-radius: 7px' "$stage/out/regreet.css"
grep -Fq 'font-family: "Test Font"' "$stage/out/regreet.css"
niri validate -c "$stage/out/niri.kdl" >/dev/null
python3 - "$ROOT/greeter/regreet.toml" <<'PY'
import pathlib, sys, tomllib
config = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert config["appearance"]["greeting_msg"] == "NBSHELL"
assert config["background"]["fit"] == "Cover"
assert config["GTK"]["font_name"].startswith("JetBrainsMono Nerd Font")
PY
grep -Fq 'border: 1px solid #7aa2f7' "$ROOT/greeter/regreet.css"
grep -Fq 'greetd-regreet' "$ROOT/setup-greeter.sh"
grep -Fq 'config.toml.before-nbshell-greeter' "$ROOT/setup-greeter.sh"

echo "Greeter validation: OK"
