#!/usr/bin/env bash
# Build and install the primary Umbriel compositor stack for nbshell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="${NBSHELL_UMBRIEL_SOURCE_DIR:-$HOME/.cache/nbshell/umbriel-sources}"
PREFIX="${NBSHELL_UMBRIEL_PREFIX:-/usr/local}"
UMBRIEL_REPO="https://github.com/noctalia-dev/umbriel.git"
PORTAL_REPO="https://github.com/noctalia-dev/xdg-desktop-portal-umbriel.git"
UMBRIEL_REVISION="e677dbbe2728ee65156bdbcc6775b0b36b388b64"
PORTAL_REVISION="d996f0c2bd4e8c868c0a143f0c9ce060f3c47ed5"
PACKAGES=(gcc git meson ninja pkgconf just wlroots0.20 wayland wayland-protocols
    libxkbcommon libinput pixman libdrm cairo pango tomlplusplus nlohmann-json jemalloc
    sdbus-cpp pipewire gtk4 wlr-randr xwayland-satellite xdg-desktop-portal)
INSTALL_SHELL=1

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-shell-install) INSTALL_SHELL=0 ;;
        -h|--help)
            printf '%s\n' \
                'setup-umbriel.sh -- build Umbriel, its portal, and the nbshell session' \
                '' \
                '  --skip-shell-install  internal: keep an already deployed nbshell runtime'
            exit 0
            ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

green() { printf '\033[32m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -u)" != 0 ] || die "Run this installer as your normal user, not root."
command -v pacman >/dev/null || die "The automatic Umbriel setup currently targets Arch Linux."

missing=()
for package in "${PACKAGES[@]}"; do
    pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
done
if [ ${#missing[@]} -gt 0 ]; then
    printf 'Installing Umbriel build/runtime packages: %s\n' "${missing[*]}"
    sudo pacman -S --needed "${missing[@]}"
fi

mkdir -p "$SOURCE_ROOT"
checkout() {
    local url="$1" destination="$2" revision="$3"
    if [ -d "$destination/.git" ]; then
        [ -z "$(git -C "$destination" status --porcelain)" ] || die "$destination has local changes; refusing to overwrite them."
        git -C "$destination" fetch --prune origin
    elif [ -e "$destination" ]; then
        die "$destination exists but is not a Git checkout."
    else
        git clone --no-checkout "$url" "$destination"
    fi
    git -C "$destination" checkout --detach "$revision"
    git -C "$destination" submodule update --init --recursive
}

checkout "$UMBRIEL_REPO" "$SOURCE_ROOT/umbriel" "$UMBRIEL_REVISION"
checkout "$PORTAL_REPO" "$SOURCE_ROOT/xdg-desktop-portal-umbriel" "$PORTAL_REVISION"

build_project() {
    local source="$1"
    local build="$source/build-nbshell"
    if [ -d "$build" ]; then
        meson setup "$build" "$source" --reconfigure --buildtype=release --prefix="$PREFIX"
    else
        meson setup "$build" "$source" --buildtype=release --prefix="$PREFIX"
    fi
    meson compile -C "$build"
    meson test -C "$build" --print-errorlogs
}

build_project "$SOURCE_ROOT/umbriel"
build_project "$SOURCE_ROOT/xdg-desktop-portal-umbriel"
INSTALL_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/nbshell-umbriel-install.XXXXXX")"
SESSION_FILE=""
trap 'rm -rf -- "$INSTALL_STAGE"; [ -z "$SESSION_FILE" ] || rm -f -- "$SESSION_FILE"' EXIT
meson install -C "$SOURCE_ROOT/umbriel/build-nbshell" --destdir "$INSTALL_STAGE"
meson install -C "$SOURCE_ROOT/xdg-desktop-portal-umbriel/build-nbshell" --destdir "$INSTALL_STAGE"
install_command=(python3 "$ROOT/shell/scripts/install-tree-transaction.py" "$INSTALL_STAGE" "$PREFIX")
if [[ $PREFIX == /usr/local ]]; then
    install_command=(sudo "${install_command[@]}")
fi
"${install_command[@]}"
systemctl --user daemon-reload

# Remove user-local unit copies from earlier builds. They override the reviewed
# root-owned units even when /usr/local is installed successfully.
for unit_dir in "$HOME/.local/share/systemd/user" "$HOME/.local/lib/systemd/user"; do
    rm -f "$unit_dir/umbriel.service" "$unit_dir/umbriel-session.target" \
        "$unit_dir/umbriel-shutdown.target" "$unit_dir/xdg-desktop-portal-umbriel.service"
done
rm -f "$HOME/.local/share/wayland-sessions/umbriel.desktop"
systemctl --user daemon-reload

# Umbriel supervises xwayland-satellite itself; a separately enabled user unit
# would race it for the X11 display socket.
XWAYLAND_DROPIN="$HOME/.config/systemd/user/xwayland-satellite.service.d/nbshell-umbriel.conf"
systemctl --user disable --now xwayland-satellite.service >/dev/null 2>&1 || true
rm -f "$XWAYLAND_DROPIN"
rmdir "$(dirname "$XWAYLAND_DROPIN")" 2>/dev/null || true
systemctl --user daemon-reload

if [ "$INSTALL_SHELL" = "1" ]; then
    "$ROOT/install.sh"
fi

# greetd and other display managers enumerate the system session folder.
SESSION_FILE="$(mktemp "${TMPDIR:-/tmp}/nbshell-umbriel-session.XXXXXX")"
printf '%s\n' \
    '[Desktop Entry]' \
    'Name=Umbriel' \
    'Comment=Umbriel Wayland Compositor with nbshell' \
    "Exec=$PREFIX/bin/start-umbriel" \
    'Type=Application' \
    'DesktopNames=Umbriel' > "$SESSION_FILE"
sudo install -m 644 "$SESSION_FILE" /usr/share/wayland-sessions/umbriel.desktop

green "Umbriel, its portal, and the nbshell integration are installed."
printf '%s\n' \
    "Nested test: nbshell compositor nested" \
    "Next login: choose Umbriel."
