#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/setup-greeter.sh"
niri validate -c "$ROOT/greeter/niri.kdl" >/dev/null
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
