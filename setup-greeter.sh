#!/usr/bin/env bash
# Install or preview the Umbriel-hosted nbshell Orbital greetd frontend.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nbshell"
if [[ -f $ROOT/shell/scripts/greeter-theme.py ]]; then
    THEME_RENDERER="$ROOT/shell/scripts/greeter-theme.py"
else
    THEME_RENDERER="$RUNTIME/scripts/greeter-theme.py"
fi
QML_SOURCE="${NBSHELL_GREETER_QML_SOURCE:-$ROOT/greeter/qml}"
TEST_ROOT="${NBSHELL_GREETER_TEST_ROOT:-}"
if [[ -n $TEST_ROOT && $TEST_ROOT != /* ]]; then
    printf '%s\n' "NBSHELL_GREETER_TEST_ROOT must be an absolute path." >&2
    exit 1
fi

prefix="${TEST_ROOT:-}"
TARGET="$prefix/etc/greetd"
PAM_TARGET="$prefix/etc/pam.d"
DATA="$prefix/usr/local/share/nbshell"
LIBEXEC="$prefix/usr/local/libexec"
SYSTEM_BIN="$prefix/usr/local/bin"
QML_TARGET="$DATA/greeter"
CONFIG="$TARGET/config.toml"
BACKUP="$TARGET/config.toml.before-nbshell-greeter"
RECOVERY="$TARGET/config.toml.nbshell-recovery"
GREETER_CONFIG="$TARGET/nbshell-greeter.toml"
GREETER_LAUNCHER="$LIBEXEC/nbshell-greeter-session"
WALLPAPER="${NBSHELL_GREETER_WALLPAPER:-}"
MODE="${1:-install}"
AUTOLOGIN_ARG="${2:-}"
AUTOLOGIN=0
ROOT_HELPER="${NBSHELL_GREETER_ROOT_HELPER:-sudo}"
[[ $ROOT_HELPER == sudo || $ROOT_HELPER == pkexec ]] \
    || { printf '%s\n' "NBSHELL_GREETER_ROOT_HELPER must be sudo or pkexec." >&2; exit 1; }

fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
as_root() {
    if [[ -n $TEST_ROOT ]]; then
        "$@"
    elif [[ $ROOT_HELPER == pkexec ]]; then
        pkexec "$@"
    else
        sudo "$@"
    fi
}

[[ $(id -u) != 0 ]] || fail "Run this tool as your normal user, not root."
command -v pacman >/dev/null || fail "The automatic greeter setup currently targets Arch Linux."
case "$MODE" in
    install|sync|preview|status) ;;
    *) fail "Usage: ./setup-greeter.sh [install [--autologin]|sync|preview|status]" ;;
esac
if [[ $AUTOLOGIN_ARG == --autologin ]]; then
    AUTOLOGIN=1
elif [[ -n $AUTOLOGIN_ARG ]]; then
    fail "Usage: ./setup-greeter.sh install [--autologin]"
fi
[[ $AUTOLOGIN == 0 || $MODE == install ]] || fail "--autologin is valid only with install."

if [[ $MODE == status ]]; then
    printf 'Frontend  orbital\n'
    printf 'Compositor Umbriel\n'
    printf 'greetd     %s\n' "$(systemctl is-active greetd 2>/dev/null || true)"
    printf 'Config     %s\n' "$CONFIG"
    printf 'Recovery   %s\n' "$RECOVERY"
    if [[ -r $QML_TARGET/shell.qml && -r $QML_TARGET/config.json ]]; then
        printf 'Orbital    installed (%s)\n' "$QML_TARGET"
    else
        printf 'Orbital    not installed (%s)\n' "$QML_TARGET"
    fi
    grep -Fq '[initial_session]' "$CONFIG" 2>/dev/null \
        && printf 'Boot       autologin (greeter appears after logout)\n' \
        || printf 'Boot       greeter\n'
    exit 0
fi

[[ -f $THEME_RENDERER ]] || fail "The installed nbshell greeter renderer is missing."
[[ -f $QML_SOURCE/shell.qml ]] || fail "The Orbital QML frontend is missing. Run install.sh first."
command -v quickshell >/dev/null || fail "Quickshell was not installed."
command -v umbriel >/dev/null || fail "Umbriel is required to validate the greeter profile."
if [[ -z $TEST_ROOT ]]; then
    [[ -x /usr/local/bin/umbriel && -x /usr/local/bin/start-umbriel ]] \
        || fail "Install the root-owned Umbriel build first with ./setup-umbriel.sh."
fi

stage="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-greeter.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
renderer_env=(env)
if [[ -n $TEST_ROOT ]]; then
    renderer_env+=(NBSHELL_UMBRIEL_LAUNCHER="$SYSTEM_BIN/start-umbriel")
fi
generated_wallpaper="$("${renderer_env[@]}" python3 "$THEME_RENDERER" "$stage" --user "$USER" --frontend orbital)"
[[ -n $WALLPAPER ]] || WALLPAPER="$generated_wallpaper"
[[ -f $WALLPAPER ]] || fail "No readable wallpaper found. Set NBSHELL_GREETER_WALLPAPER to an image file."
umbriel validate -c "$stage/umbriel.toml"

if [[ $MODE == preview ]]; then
    python3 - "$stage/config.json" "$WALLPAPER" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["wallpaper"] = str(pathlib.Path(sys.argv[2]).resolve())
data["username"] = data.get("username") or "preview"
data["autoStartAuthentication"] = False
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
    exec env NBSHELL_GREETER_PREVIEW=1 NBSHELL_GREETER_CONFIG="$stage/config.json" \
        quickshell -p "$QML_SOURCE"
fi

if [[ $MODE == install && -z $TEST_ROOT ]]; then
    as_root pacman -S --needed greetd quickshell
fi

as_root install -d -m 755 "$TARGET" "$PAM_TARGET" "$DATA" "$LIBEXEC" "$QML_TARGET"
if [[ -f $CONFIG && ! -f $BACKUP ]]; then
    as_root install -m 644 "$CONFIG" "$BACKUP"
fi
as_root install -m 644 "$ROOT/greeter/nbshell-greetd.pam" "$PAM_TARGET/nbshell-greetd"
as_root install -m 755 "$ROOT/greeter/nbshell-greeter-session" "$GREETER_LAUNCHER"
as_root install -m 644 "$stage/umbriel.toml" "$GREETER_CONFIG"
as_root install -m 644 "$stage/config.json" "$QML_TARGET/config.json"
as_root install -m 644 \
    "$QML_SOURCE/shell.qml" "$QML_SOURCE/GreeterView.qml" \
    "$QML_SOURCE/OrbitalClock.qml" "$QML_SOURCE/ClockMath.js" \
    "$QML_SOURCE/qmldir" "$QML_TARGET/"

case "${WALLPAPER##*.}" in
    jpg|JPG|jpeg|JPEG)
        as_root install -m 644 "$WALLPAPER" "$DATA/greeter-wallpaper.jpg"
        ;;
    *)
        command -v magick >/dev/null || fail "Use a JPEG wallpaper or install ImageMagick for conversion."
        temporary="$stage/greeter-wallpaper.jpg"
        magick "$WALLPAPER" -quality 94 "$temporary"
        as_root install -m 644 "$temporary" "$DATA/greeter-wallpaper.jpg"
        ;;
esac

recovery_config="$stage/recovery.toml"
cat >"$recovery_config" <<'EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "/usr/bin/agreety --cmd /bin/sh"
EOF
as_root install -m 644 "$recovery_config" "$RECOVERY"

if [[ $MODE == install ]]; then
    temporary_config="$stage/config.toml"
    {
        printf '%s\n' \
            '[terminal]' \
            'vt = 1' \
            '' \
            '[general]' \
            'service = "nbshell-greetd"' \
            '' \
            '[default_session]' \
            'user = "greeter"' \
            'command = "/usr/local/libexec/nbshell-greeter-session orbital"'
        if [[ $AUTOLOGIN == 1 ]]; then
            printf '%s\n' \
                '' \
                '[initial_session]' \
                "user = \"$USER\"" \
                'command = "/usr/local/bin/start-umbriel"'
        fi
    } >"$temporary_config"
fi

if [[ -z $TEST_ROOT ]]; then
    as_root systemd-tmpfiles --create
fi
as_root test -x "$SYSTEM_BIN/umbriel"
as_root test -x "$SYSTEM_BIN/start-umbriel"
as_root test -x "$GREETER_LAUNCHER"
as_root test -r "$PAM_TARGET/nbshell-greetd"
as_root test -r "$GREETER_CONFIG"
as_root test -r "$RECOVERY"
as_root test -r "$DATA/greeter-wallpaper.jpg"
as_root test -x "$prefix/usr/bin/quickshell"
as_root test -x "$prefix/usr/bin/agreety"
as_root test -r "$QML_TARGET/config.json"
as_root test -r "$QML_TARGET/shell.qml"

# Commit the boot selector only after compositor, frontend, PAM, wallpaper and
# independent agreety recovery payloads have all been verified.
if [[ $MODE == install ]]; then
    as_root install -m 644 "$temporary_config" "$CONFIG"
    if [[ -n $TEST_ROOT ]]; then
        :
    elif systemctl is-enabled --quiet greetd.service 2>/dev/null; then
        :
    elif systemctl is-enabled --quiet display-manager.service 2>/dev/null; then
        warn "Another display manager is enabled; Orbital is staged but greetd was not enabled."
    else
        as_root systemctl enable greetd.service
    fi
fi

# Retired frontend files are removed only after the new path is complete.
as_root rm -f "$TARGET/nbshell-greeter.kdl" "$TARGET/regreet.toml" "$TARGET/regreet.css"

case "$MODE" in
    sync)
        ok "The Orbital greeter now matches the current nbshell theme and wallpaper."
        ;;
    install)
        ok "The Umbriel-hosted nbshell Orbital greeter is staged."
        printf '%s\n' \
            "It becomes active after a reboot; greetd and the current session were not restarted." \
            "Independent recovery: copy $RECOVERY to $CONFIG from a TTY." \
            "Historical backup: $BACKUP"
        ;;
esac
