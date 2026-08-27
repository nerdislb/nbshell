#!/usr/bin/env bash
# Install or preview the nbshell greetd frontend.
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
if [[ -n $TEST_ROOT ]]; then
    if [[ $TEST_ROOT != /* ]]; then
        printf '%s\n' "NBSHELL_GREETER_TEST_ROOT must be an absolute path." >&2
        exit 1
    fi
    TARGET="$TEST_ROOT/etc/greetd"
    PAM_TARGET="$TEST_ROOT/etc/pam.d"
    DATA="$TEST_ROOT/usr/local/share/nbshell"
else
    TARGET=/etc/greetd
    PAM_TARGET=/etc/pam.d
    DATA=/usr/local/share/nbshell
fi
QML_TARGET="$DATA/greeter"
CONFIG="$TARGET/config.toml"
BACKUP="$TARGET/config.toml.before-nbshell-greeter"
WALLPAPER="${NBSHELL_GREETER_WALLPAPER:-}"
MODE="${1:-install}"
REQUESTED_FRONTEND="${2:-}"
AUTOLOGIN_ARG="${3:-}"
AUTOLOGIN=0
ROOT_HELPER="${NBSHELL_GREETER_ROOT_HELPER:-sudo}"
[[ $ROOT_HELPER == sudo || $ROOT_HELPER == pkexec ]] \
    || { printf '%s\n' "NBSHELL_GREETER_ROOT_HELPER must be sudo or pkexec." >&2; exit 1; }

fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
if [[ $AUTOLOGIN_ARG == --autologin ]]; then
    AUTOLOGIN=1
elif [[ -n $AUTOLOGIN_ARG ]]; then
    fail "Usage: ./setup-greeter.sh install [orbital|regreet] [--autologin]"
fi
as_root() {
    if [[ -n $TEST_ROOT ]]; then
        "$@"
    elif [[ $ROOT_HELPER == pkexec ]]; then
        pkexec "$@"
    else
        sudo "$@"
    fi
}

[ "$(id -u)" != 0 ] || fail "Run this tool as your normal user, not root."
command -v pacman >/dev/null || fail "The automatic greeter setup currently targets Arch Linux."
command -v niri >/dev/null || fail "Niri is required for the isolated greetd frontend session."
case "$MODE" in
    install|sync|preview|status) ;;
    activate)
        [[ $REQUESTED_FRONTEND == orbital || $REQUESTED_FRONTEND == regreet ]] \
            || fail "Usage: ./setup-greeter.sh activate orbital|regreet"
        ;;
    *) fail "Usage: ./setup-greeter.sh [install [orbital|regreet] [--autologin]|sync|preview|status|activate orbital|regreet]" ;;
esac
if [[ $MODE == install && -n $REQUESTED_FRONTEND && $REQUESTED_FRONTEND != orbital && $REQUESTED_FRONTEND != regreet ]]; then
    fail "Usage: ./setup-greeter.sh install [orbital|regreet]"
fi
if [[ $AUTOLOGIN == 1 && $MODE != install ]]; then
    fail "--autologin is valid only with install."
fi

active_frontend() {
    if [[ -r $TARGET/nbshell-greeter.kdl ]] && grep -Fq '/usr/bin/quickshell -p /usr/local/share/nbshell/greeter' "$TARGET/nbshell-greeter.kdl"; then
        printf 'orbital\n'
    else
        printf 'regreet\n'
    fi
}

if [[ $MODE == status ]]; then
    printf 'Frontend  %s\n' "$(active_frontend)"
    printf 'greetd    %s\n' "$(systemctl is-active greetd 2>/dev/null || true)"
    printf 'Config    %s\n' "$CONFIG"
    if [[ -r $QML_TARGET/shell.qml && -r $QML_TARGET/config.json ]]; then
        printf 'Orbital   installed (%s)\n' "$QML_TARGET"
    else
        printf 'Orbital   not installed (%s)\n' "$QML_TARGET"
    fi
    if grep -Fq '[initial_session]' "$CONFIG" 2>/dev/null; then
        printf 'Boot       autologin (greeter appears after logout)\n'
    else
        printf 'Boot       greeter\n'
    fi
    exit 0
fi

case "$MODE" in
    install) FRONTEND="${REQUESTED_FRONTEND:-orbital}" ;;
    activate) FRONTEND="$REQUESTED_FRONTEND" ;;
    sync) FRONTEND="$(active_frontend)" ;;
    preview) FRONTEND=orbital ;;
esac

[[ -f $THEME_RENDERER ]] || fail "The installed nbshell greeter renderer is missing."
if [[ $FRONTEND == orbital ]]; then
    [[ -f $QML_SOURCE/shell.qml ]] || fail "The Orbital QML frontend is missing. Run install.sh first."
    command -v quickshell >/dev/null || fail "Quickshell was not installed."
fi

stage="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-greeter.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
generated_wallpaper="$(python3 "$THEME_RENDERER" "$stage" --user "$USER" --frontend "$FRONTEND")"
[ -n "$WALLPAPER" ] || WALLPAPER="$generated_wallpaper"
[ -f "$WALLPAPER" ] || fail "No readable wallpaper found. Set NBSHELL_GREETER_WALLPAPER to an image file."
niri validate -c "$stage/niri.kdl"

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

if [[ $MODE == install ]]; then
    if [[ -z $TEST_ROOT ]]; then
        packages=(greetd-regreet)
        [[ $FRONTEND != orbital ]] || packages+=(quickshell)
        as_root pacman -S --needed "${packages[@]}"
    fi
fi
command -v regreet >/dev/null || fail "ReGreet is required as the recovery frontend."

as_root install -d -m 755 "$TARGET" "$PAM_TARGET" "$DATA"
if [[ -f $CONFIG && ! -f $BACKUP ]]; then
    as_root install -m 644 "$CONFIG" "$BACKUP"
fi
as_root install -m 644 "$ROOT/greeter/regreet.toml" "$TARGET/regreet.toml"
as_root install -m 644 "$ROOT/greeter/nbshell-greetd.pam" "$PAM_TARGET/nbshell-greetd"
as_root install -m 644 "$stage/regreet.css" "$TARGET/regreet.css"
as_root install -m 644 "$stage/fingerprint.svg" "$DATA/fingerprint.svg"
if [[ $FRONTEND == orbital ]]; then
    as_root install -d -m 755 "$QML_TARGET"
    as_root install -m 644 "$stage/config.json" "$QML_TARGET/config.json"
    as_root install -m 644 \
        "$QML_SOURCE/shell.qml" "$QML_SOURCE/GreeterView.qml" \
        "$QML_SOURCE/OrbitalClock.qml" "$QML_SOURCE/ClockMath.js" \
        "$QML_SOURCE/qmldir" "$QML_TARGET/"
fi

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
            'command = "dbus-run-session niri --config /etc/greetd/nbshell-greeter.kdl"'
        if [[ $AUTOLOGIN == 1 ]]; then
            [[ -x $HOME/.local/bin/start-umbriel ]] \
                || fail "--autologin requires $HOME/.local/bin/start-umbriel."
            printf '%s\n' \
                '' \
                '[initial_session]' \
                "user = \"$USER\"" \
                "command = \"$HOME/.local/bin/start-umbriel\""
        fi
    } >"$temporary_config"
fi

if [[ -z $TEST_ROOT ]]; then
    as_root systemd-tmpfiles --create
fi
as_root test -x /usr/bin/regreet
as_root test -r "$PAM_TARGET/nbshell-greetd"
as_root test -r "$TARGET/regreet.toml"
as_root test -r "$TARGET/regreet.css"
as_root test -r "$DATA/greeter-wallpaper.jpg"
if [[ $FRONTEND == orbital ]]; then
    as_root test -x /usr/bin/quickshell
    as_root test -r "$QML_TARGET/config.json"
    as_root test -r "$QML_TARGET/shell.qml"
fi

# Commit the frontend switch only after every dependency has been installed and
# verified. A failed copy above therefore leaves the previous bootable frontend.
as_root install -m 644 "$stage/niri.kdl" "$TARGET/nbshell-greeter.kdl"
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

case "$MODE" in
    sync)
        ok "The $FRONTEND greeter now matches the current nbshell theme and wallpaper."
        ;;
    activate)
        ok "The $FRONTEND frontend is staged for the next greetd start."
        printf '%s\n' "Reboot to activate it; the current graphical session was not interrupted."
        ;;
    install)
        ok "nbshell $FRONTEND greeter installed."
        printf '%s\n' \
            "It becomes active after a reboot; greetd cannot reload its running configuration." \
            "The current session was not interrupted." \
            "Recovery frontend: ./setup-greeter.sh activate regreet" \
            "Recovery backup: $BACKUP" \
            "TTY recovery: Ctrl+Alt+F2, then copy the backup back to $CONFIG."
        ;;
esac
