#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/setup-greeter.sh"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/bin/nbshell"
niri validate -c "$ROOT/greeter/niri.kdl" >/dev/null
python3 -m py_compile "$ROOT/shell/scripts/greeter-theme.py"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
test_config="$stage/user-config"
mkdir -p "$test_config/nbshell/themes/test/backgrounds"
cp "$ROOT/themes/tokyo-night/colors.toml" "$test_config/nbshell/themes/test/colors.toml"
touch "$test_config/nbshell/themes/test/backgrounds/test.jpg"
printf '{"theme":"test","radius":7,"font":"Test Font","lockDim":41}\n' > "$test_config/nbshell/config.json"

XDG_CONFIG_HOME="$test_config" python3 "$ROOT/shell/scripts/greeter-theme.py" \
    "$stage/orbital" --user test-user --frontend orbital >/dev/null
XDG_CONFIG_HOME="$test_config" python3 "$ROOT/shell/scripts/greeter-theme.py" \
    "$stage/regreet" --user test-user --frontend regreet >/dev/null

grep -Fq 'border-radius: 7px' "$stage/orbital/regreet.css"
grep -Fq 'font-family: "Test Font"' "$stage/orbital/regreet.css"
grep -Fq '/usr/bin/quickshell -p /usr/local/share/nbshell/greeter' "$stage/orbital/niri.kdl"
grep -Fq '/usr/bin/regreet' "$stage/regreet/niri.kdl"
niri validate -c "$stage/orbital/niri.kdl" >/dev/null
niri validate -c "$stage/regreet/niri.kdl" >/dev/null

python3 - "$ROOT" "$stage/orbital/config.json" "$ROOT/greeter/regreet.toml" <<'PY'
import json, pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
config = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert config["username"] == "test-user"
assert config["font"] == "Test Font"
assert config["dimOpacity"] == 0.41
assert config["sessions"]
assert all(isinstance(row["command"], list) and row["command"] for row in config["sessions"])
assert all(all(isinstance(arg, str) and arg for arg in row["command"]) for row in config["sessions"])

regreet = tomllib.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
assert regreet["appearance"]["greeting_msg"] == "NBSHELL"
assert regreet["background"]["fit"] == "Cover"

shell = (root / "greeter/qml/shell.qml").read_text(encoding="utf-8")
view = (root / "greeter/qml/GreeterView.qml").read_text(encoding="utf-8")
for required in ("Quickshell.Services.Greetd", "Greetd.createSession", "Greetd.respond", "Greetd.launch", "Greetd.cancelSession"):
    assert required in shell, required
for forbidden in ("PamContext", "WlSessionLock", "omarchy-system", "bash -c", "sh -c"):
    assert forbidden not in shell + view, forbidden
assert "NBSHELL_GREETER_PREVIEW" in shell
assert "previewMode ||" in shell
assert "onQuitPreview: Qt.quit()" in shell
assert "pendingPassword" not in shell
assert "function submitResponse(response)" in shell
assert "echoMode: root.echoResponse ? TextInput.Normal : TextInput.Password" in view
assert "externalAuthActive" in shell + view
assert "externalAuthActive = false;" in shell
assert 'normalizedMessage.includes("finger")' in shell
assert "authBoost" not in (root / "greeter/qml/OrbitalClock.qml").read_text(encoding="utf-8")
assert "START PASSWORD LOGIN" in view
assert "TOUCH SENSOR OR WAIT FOR PASSWORD" not in view
PY

grep -Fq 'packages=(greetd-regreet)' "$ROOT/setup-greeter.sh"
grep -Fq 'packages+=(quickshell)' "$ROOT/setup-greeter.sh"
grep -Fq 'config.toml.before-nbshell-greeter' "$ROOT/setup-greeter.sh"
grep -Fq 'activate orbital|regreet' "$ROOT/bin/nbshell"
grep -Fq 'Orbital Lock' "$ROOT/THIRD_PARTY.md"

# Exercise install, immutable backup creation, file modes, and both frontend
# switches without sudo or writes outside the temporary root.
fake_root="$stage/root"
mkdir -p "$fake_root/etc/greetd" "$fake_root/etc/pam.d"
printf 'original greetd config\n' >"$fake_root/etc/greetd/config.toml"
printf 'pam sentinel\n' >"$fake_root/etc/pam.d/greetd"
NBSHELL_GREETER_TEST_ROOT="$fake_root" \
NBSHELL_GREETER_WALLPAPER="$test_config/nbshell/themes/test/backgrounds/test.jpg" \
XDG_CONFIG_HOME="$test_config" \
    "$ROOT/setup-greeter.sh" install orbital >/dev/null
cmp -s "$fake_root/etc/greetd/config.toml.before-nbshell-greeter" <(printf 'original greetd config\n')
cmp -s "$fake_root/etc/pam.d/greetd" <(printf 'pam sentinel\n')
grep -Fq 'dbus-run-session niri --config /etc/greetd/nbshell-greeter.kdl' "$fake_root/etc/greetd/config.toml"
grep -Fq '/usr/bin/quickshell -p /usr/local/share/nbshell/greeter' "$fake_root/etc/greetd/nbshell-greeter.kdl"
test "$(stat -c %a "$fake_root/etc/greetd/config.toml")" = 644
test "$(stat -c %a "$fake_root/usr/local/share/nbshell/greeter/shell.qml")" = 644

NBSHELL_GREETER_TEST_ROOT="$fake_root" \
NBSHELL_GREETER_QML_SOURCE="$stage/missing-orbital-source" \
NBSHELL_GREETER_WALLPAPER="$test_config/nbshell/themes/test/backgrounds/test.jpg" \
XDG_CONFIG_HOME="$test_config" \
    "$ROOT/setup-greeter.sh" activate regreet >/dev/null
grep -Fq '/usr/bin/regreet' "$fake_root/etc/greetd/nbshell-greeter.kdl"
cmp -s "$fake_root/etc/greetd/config.toml.before-nbshell-greeter" <(printf 'original greetd config\n')

NBSHELL_GREETER_TEST_ROOT="$fake_root" \
NBSHELL_GREETER_WALLPAPER="$test_config/nbshell/themes/test/backgrounds/test.jpg" \
XDG_CONFIG_HOME="$test_config" \
    "$ROOT/setup-greeter.sh" activate orbital >/dev/null
grep -Fq '/usr/bin/quickshell -p /usr/local/share/nbshell/greeter' "$fake_root/etc/greetd/nbshell-greeter.kdl"

qml_test_runner=/usr/lib/qt6/bin/qmltestrunner
if [[ -x $qml_test_runner ]]; then
    env -u DISPLAY -u WAYLAND_DISPLAY \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
        "$qml_test_runner" -input "$ROOT/tests" -o -,txt
fi

python3 "$ROOT/tests/greetd-mock.py"

echo "Greeter validation: OK"
