#!/usr/bin/env bash
set -euo pipefail

assert_not_grep() {
    local status
    if grep "$@"; then
        printf 'Unexpected grep match: %s\n' "$*" >&2
        return 1
    else
        status=$?
        if [ "$status" -ne 1 ]; then
            printf 'grep failed with status %s: %s\n' "$status" "$*" >&2
            return "$status"
        fi
    fi
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT/setup-greeter.sh" "$ROOT/install.sh" "$ROOT/bin/nbshell" \
    "$ROOT/greeter/nbshell-greeter-session"
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
    "$ROOT/shell/scripts/greeter-theme.py"

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
test_config="$stage/user-config"
mkdir -p "$test_config/nbshell/themes/test/backgrounds"
cp "$ROOT/themes/tokyo-night/colors.toml" "$test_config/nbshell/themes/test/colors.toml"
touch "$test_config/nbshell/themes/test/backgrounds/test.jpg"
printf '{"theme":"test","radius":7,"font":"Test Font","lockDim":41,"motionProfile":"reduced"}\n' > "$test_config/nbshell/config.json"
printf '#!/usr/bin/env sh\nexit 0\n' > "$stage/start-umbriel"
chmod +x "$stage/start-umbriel"

NBSHELL_UMBRIEL_LAUNCHER="$stage/start-umbriel" \
XDG_CONFIG_HOME="$test_config" python3 "$ROOT/shell/scripts/greeter-theme.py" \
    "$stage/orbital" --user test-user --frontend orbital >/dev/null
umbriel validate -c "$stage/orbital/umbriel.toml" >/dev/null
test ! -e "$stage/orbital/regreet.css"
test ! -e "$stage/orbital/regreet.toml"

python3 - "$ROOT" "$stage/orbital/config.json" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
config = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert config["username"] == "test-user"
assert config["font"] == "Test Font"
assert config["dimOpacity"] == 0.41
assert config["reducedMotion"] is True
assert len(config["sessions"]) == 1
assert config["sessions"][0]["name"] == "Umbriel"
assert pathlib.Path(config["sessions"][0]["command"][0]).name == "start-umbriel"

shell = (root / "greeter/qml/shell.qml").read_text(encoding="utf-8")
view = (root / "greeter/qml/GreeterView.qml").read_text(encoding="utf-8")
for required in ("Quickshell.Services.Greetd", "Greetd.createSession", "Greetd.respond", "Greetd.launch", "Greetd.cancelSession"):
    assert required in shell, required
for forbidden in ("PamContext", "WlSessionLock", "omarchy-system", "bash -c", "sh -c"):
    assert forbidden not in shell + view, forbidden
assert "NBSHELL_GREETER_PREVIEW" in shell
assert "onQuitPreview: Qt.quit()" in shell
assert "function submitResponse(response)" in shell
assert "authenticationRetryPending" in shell
assert "AUTHENTICATION RESET TIMED OUT · PRESS ESC TO CANCEL" in shell
for required in (
    "reducedMotion",
    "Accessible.role: Accessible.Button",
    "activeFocusOnTab",
    "Accessible.onPressAction",
    "Accessible.passwordEdit",
    "Accessible.focusable: enabled",
):
    assert required in view, required
action_label = view[view.index("component ActionLabel:"):]
assert action_label.count("if (!event.isAutoRepeat) actionRoot.activate();") == 3
PY

grep -Fq 'config.toml.before-nbshell-greeter' "$ROOT/setup-greeter.sh"
grep -Fq 'config.toml.nbshell-recovery' "$ROOT/setup-greeter.sh"
grep -Fq 'service = "nbshell-greetd"' "$ROOT/setup-greeter.sh"
grep -Fq 'auth       include      system-local-login' "$ROOT/greeter/nbshell-greetd.pam"
assert_not_grep -Eq '^[[:space:]]*auth[[:space:]].*pam_fprintd' "$ROOT/greeter/nbshell-greetd.pam"
python3 - "$ROOT/setup-greeter.sh" <<'PY'
from pathlib import Path
import sys

matches = [
    line.strip()
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if "regreet" in line.lower()
]
allowed_cleanup = (
    'as_root rm -f "$TARGET/nbshell-greeter.kdl" "$TARGET/regreet.toml" '
    '"$TARGET/regreet.css"'
)
assert matches == [allowed_cleanup], matches
PY
grep -Fq 'install) "$GREETER_SETUP" install' "$ROOT/bin/nbshell"

setup_help="$("$ROOT/setup.sh" --help)"
grep -Fq -- '--with-greeter' <<<"$setup_help"
grep -Fq -- '--no-greeter' <<<"$setup_help"
assert_not_grep -Fq -- '--niri-only' <<<"$setup_help"
if "$ROOT/setup.sh" --no-packages --with-greeter >/dev/null 2>&1; then
    echo "Conflicting greeter setup options unexpectedly succeeded" >&2
    exit 1
fi
if "$ROOT/setup.sh" --with-greeter --no-greeter >/dev/null 2>&1; then
    echo "Contradictory greeter policy flags unexpectedly succeeded" >&2
    exit 1
fi

fake_root="$stage/root"
mkdir -p "$fake_root/etc/greetd" "$fake_root/etc/pam.d" \
    "$fake_root/usr/local/bin" "$fake_root/usr/bin"
printf 'original greetd config\n' >"$fake_root/etc/greetd/config.toml"
printf 'pam sentinel\n' >"$fake_root/etc/pam.d/greetd"
for executable in "$fake_root/usr/local/bin/umbriel" \
    "$fake_root/usr/local/bin/start-umbriel" "$fake_root/usr/bin/quickshell" \
    "$fake_root/usr/bin/agreety"; do
    printf '#!/usr/bin/env sh\nexit 0\n' >"$executable"
    chmod +x "$executable"
done

NBSHELL_GREETER_TEST_ROOT="$fake_root" \
NBSHELL_GREETER_WALLPAPER="$test_config/nbshell/themes/test/backgrounds/test.jpg" \
XDG_CONFIG_HOME="$test_config" \
    "$ROOT/setup-greeter.sh" install >/dev/null
cmp -s "$fake_root/etc/greetd/config.toml.before-nbshell-greeter" <(printf 'original greetd config\n')
cmp -s "$fake_root/etc/pam.d/greetd" <(printf 'pam sentinel\n')
cmp -s "$fake_root/etc/pam.d/nbshell-greetd" "$ROOT/greeter/nbshell-greetd.pam"
grep -Fq 'command = "/usr/local/libexec/nbshell-greeter-session orbital"' "$fake_root/etc/greetd/config.toml"
grep -Fq 'command = "/usr/bin/agreety --cmd /bin/sh"' "$fake_root/etc/greetd/config.toml.nbshell-recovery"
assert_not_grep -Fq '[initial_session]' "$fake_root/etc/greetd/config.toml"
grep -Fq '/usr/local/bin/umbriel' "$fake_root/usr/local/libexec/nbshell-greeter-session"
umbriel validate -c "$fake_root/etc/greetd/nbshell-greeter.toml" >/dev/null
test "$(stat -c %a "$fake_root/etc/greetd/config.toml")" = 644
test "$(stat -c %a "$fake_root/etc/pam.d/nbshell-greetd")" = 644
test "$(stat -c %a "$fake_root/usr/local/libexec/nbshell-greeter-session")" = 755
test "$(stat -c %a "$fake_root/usr/local/share/nbshell/greeter/shell.qml")" = 644
# QML files are a single interface bundle. In particular, a new required
# GreeterView property must never ship with an older shell.qml caller.
for component in shell.qml GreeterView.qml OrbitalClock.qml ClockMath.js qmldir; do
    cmp -s "$ROOT/greeter/qml/$component" "$fake_root/usr/local/share/nbshell/greeter/$component"
done

# Reproduce the September 2026 invisible-greeter incident. A still-running
# Quickshell process is not readiness: mismatched components must block sync
# before any active files change, even when initial greetd setup already exists.
cp -a "$fake_root" "$stage/before-rejected-sync"
cp -a "$ROOT/greeter/qml" "$stage/broken-qml"
sed -i '/reducedMotion: shell.reducedMotion/d' "$stage/broken-qml/shell.qml"
if NBSHELL_GREETER_TEST_ROOT="$fake_root" \
    NBSHELL_GREETER_QML_SOURCE="$stage/broken-qml" \
    NBSHELL_GREETER_WALLPAPER="$test_config/nbshell/themes/test/backgrounds/test.jpg" \
    XDG_CONFIG_HOME="$test_config" \
    "$ROOT/setup-greeter.sh" sync >"$stage/rejected.log" 2>&1; then
    echo "Invisible greeter was unexpectedly accepted" >&2
    exit 1
fi
grep -Fq 'Greeter component creation failed' "$stage/rejected.log"
diff -r "$stage/before-rejected-sync/etc" "$fake_root/etc"
diff -r "$stage/before-rejected-sync/usr/local/share/nbshell/greeter" \
    "$fake_root/usr/local/share/nbshell/greeter"

# A successful exchange keeps the previous complete bundle as a recovery copy.
printf 'old bundle marker\n' >"$fake_root/usr/local/share/nbshell/greeter/rollback-marker"

NBSHELL_GREETER_TEST_ROOT="$fake_root" \
NBSHELL_GREETER_WALLPAPER="$test_config/nbshell/themes/test/backgrounds/test.jpg" \
XDG_CONFIG_HOME="$test_config" \
    "$ROOT/setup-greeter.sh" install --autologin >/dev/null
grep -Fq '[initial_session]' "$fake_root/etc/greetd/config.toml"
grep -Fq 'command = "/usr/local/bin/start-umbriel"' "$fake_root/etc/greetd/config.toml"
cmp -s "$fake_root/etc/greetd/config.toml.before-nbshell-greeter" <(printf 'original greetd config\n')
test ! -e "$fake_root/usr/local/share/nbshell/greeter/rollback-marker"
test "$(find "$fake_root/usr/local/share/nbshell" -name rollback-marker | wc -l)" = 1

# Test the shipped checker against the installed bundle, too.
python3 "$ROOT/shell/scripts/greeter-check.py" "$fake_root/usr/local/share/nbshell/greeter"

bash "$ROOT/tests/qml.sh"
python3 "$ROOT/tests/greetd-mock.py"

echo "Umbriel Orbital greeter validation: OK"
