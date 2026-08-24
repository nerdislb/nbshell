#!/usr/bin/env bash
# Install the optional nbshell-styled ReGreet frontend for greetd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=/etc/greetd
DATA=/usr/local/share/nbshell
CONFIG="$TARGET/config.toml"
BACKUP="$TARGET/config.toml.before-nbshell-greeter"
WALLPAPER="${NBSHELL_GREETER_WALLPAPER:-}"

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }

[ "$(id -u)" != 0 ] || die "Run this installer as your normal user, not root."
command -v pacman >/dev/null || die "The automatic greeter setup currently targets Arch Linux."

if [ -z "$WALLPAPER" ] && [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/config.json" ]; then
    WALLPAPER="$(python3 - "${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/config.json" <<'PY'
import json, pathlib, sys
try:
    value = json.loads(pathlib.Path(sys.argv[1]).read_text()).get("wallpaperOverride", "")
    print(pathlib.Path(value).expanduser() if value else "")
except (OSError, ValueError):
    print("")
PY
)"
fi
[ -f "$WALLPAPER" ] || die "No readable wallpaper found. Set NBSHELL_GREETER_WALLPAPER to a JPEG or PNG file."

sudo pacman -S --needed greetd-regreet
command -v regreet >/dev/null || die "ReGreet was not installed."
niri validate -c "$ROOT/greeter/niri.kdl"

sudo install -d -m 755 "$TARGET" "$DATA"
if [ -f "$CONFIG" ] && [ ! -f "$BACKUP" ]; then
    sudo install -m 644 "$CONFIG" "$BACKUP"
fi
sudo install -m 644 "$ROOT/greeter/regreet.toml" "$TARGET/regreet.toml"
sudo install -m 644 "$ROOT/greeter/regreet.css" "$TARGET/regreet.css"
sudo install -m 644 "$ROOT/greeter/niri.kdl" "$TARGET/nbshell-greeter.kdl"

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

temporary_config="$(mktemp "${TMPDIR:-/tmp}/nbshell-greetd.XXXXXX.toml")"
trap 'rm -f -- "${temporary:-}" "$temporary_config"' EXIT
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

sudo systemd-tmpfiles --create
sudo test -x /usr/bin/regreet
sudo test -r "$TARGET/regreet.toml"
sudo test -r "$TARGET/regreet.css"
sudo test -r "$DATA/greeter-wallpaper.jpg"

ok "nbshell ReGreet installed."
printf '%s\n' \
    "It becomes active on the next logout or reboot; the current session was not interrupted." \
    "Recovery backup: $BACKUP" \
    "TTY recovery: Ctrl+Alt+F2, then copy the backup back to $CONFIG."
