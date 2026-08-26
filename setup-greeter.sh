#!/usr/bin/env bash
# Install the optional nbshell-styled ReGreet frontend for greetd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nbshell"
if [[ -f $ROOT/shell/scripts/greeter-theme.py ]]; then
    THEME_RENDERER="$ROOT/shell/scripts/greeter-theme.py"
else
    THEME_RENDERER="$RUNTIME/scripts/greeter-theme.py"
fi
TARGET=/etc/greetd
DATA=/usr/local/share/nbshell
CONFIG="$TARGET/config.toml"
BACKUP="$TARGET/config.toml.before-nbshell-greeter"
WALLPAPER="${NBSHELL_GREETER_WALLPAPER:-}"
MODE="${1:-install}"

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }

[ "$(id -u)" != 0 ] || die "Run this installer as your normal user, not root."
command -v pacman >/dev/null || die "The automatic greeter setup currently targets Arch Linux."
[[ $MODE == install || $MODE == sync ]] || die "Usage: ./setup-greeter.sh [install|sync]"

stage="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-greeter.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
[[ -f $THEME_RENDERER ]] || die "The installed nbshell greeter renderer is missing."
generated_wallpaper="$(python3 "$THEME_RENDERER" "$stage")"
[ -n "$WALLPAPER" ] || WALLPAPER="$generated_wallpaper"
[ -f "$WALLPAPER" ] || die "No readable wallpaper found. Set NBSHELL_GREETER_WALLPAPER to an image file."

if [[ $MODE == install ]]; then
    sudo pacman -S --needed greetd-regreet
fi
command -v regreet >/dev/null || die "ReGreet was not installed."
niri validate -c "$stage/niri.kdl"

sudo install -d -m 755 "$TARGET" "$DATA"
if [ -f "$CONFIG" ] && [ ! -f "$BACKUP" ]; then
    sudo install -m 644 "$CONFIG" "$BACKUP"
fi
sudo install -m 644 "$ROOT/greeter/regreet.toml" "$TARGET/regreet.toml"
sudo install -m 644 "$stage/regreet.css" "$TARGET/regreet.css"
sudo install -m 644 "$stage/niri.kdl" "$TARGET/nbshell-greeter.kdl"
sudo install -m 644 "$stage/fingerprint.svg" "$DATA/fingerprint.svg"

case "${WALLPAPER##*.}" in
    jpg|JPG|jpeg|JPEG)
        sudo install -m 644 "$WALLPAPER" "$DATA/greeter-wallpaper.jpg"
        ;;
    png|PNG)
        command -v magick >/dev/null || die "ImageMagick is required to convert a PNG greeter wallpaper to JPEG."
        temporary="$(mktemp "${TMPDIR:-/tmp}/nbshell-greeter.XXXXXX.jpg")"
        trap 'rm -f -- "$temporary"' EXIT
        magick "$WALLPAPER" -quality 94 "$temporary"
        sudo install -m 644 "$temporary" "$DATA/greeter-wallpaper.jpg"
        ;;
    *)
        command -v magick >/dev/null || die "Use a JPEG/PNG wallpaper or install ImageMagick for conversion."
        temporary="$(mktemp "${TMPDIR:-/tmp}/nbshell-greeter.XXXXXX.jpg")"
        trap 'rm -f -- "$temporary"' EXIT
        magick "$WALLPAPER" -quality 94 "$temporary"
        sudo install -m 644 "$temporary" "$DATA/greeter-wallpaper.jpg"
        ;;
esac

if [[ $MODE == install ]]; then
    temporary_config="$stage/config.toml"
    cat > "$temporary_config" <<EOF
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dbus-run-session niri --config $TARGET/nbshell-greeter.kdl"

[initial_session]
user = "$USER"
command = "$HOME/.local/bin/start-umbriel"
EOF
    sudo install -o root -g root -m 644 "$temporary_config" "$CONFIG"
fi

sudo systemd-tmpfiles --create
sudo test -x /usr/bin/regreet
sudo test -r "$TARGET/regreet.toml"
sudo test -r "$TARGET/regreet.css"
sudo test -r "$DATA/greeter-wallpaper.jpg"

if [[ $MODE == sync ]]; then
    ok "ReGreet now matches the current nbshell theme and wallpaper."
else
    ok "nbshell ReGreet installed."
    printf '%s\n' \
        "It becomes active after a reboot; greetd cannot reload its running configuration." \
        "The current session was not interrupted." \
        "Recovery backup: $BACKUP" \
        "TTY recovery: Ctrl+Alt+F2, then copy the backup back to $CONFIG."
fi
