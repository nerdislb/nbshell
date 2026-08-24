#!/usr/bin/env bash
# Build and install the optional Umbriel compositor stack for nbshell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="${NBSHELL_UMBRIEL_SOURCE_DIR:-$HOME/.cache/nbshell/umbriel-sources}"
PREFIX="${NBSHELL_UMBRIEL_PREFIX:-$HOME/.local}"
UMBRIEL_REPO="https://github.com/noctalia-dev/umbriel.git"
PORTAL_REPO="https://github.com/noctalia-dev/xdg-desktop-portal-umbriel.git"
UMBRIEL_PATCH="$ROOT/shell/patches/umbriel-fullscreen-maximize.patch"
PACKAGES=(gcc git meson ninja pkgconf just wlroots0.20 wayland wayland-protocols
    libxkbcommon libinput pixman libdrm cairo pango tomlplusplus nlohmann-json jemalloc
    sdbus-cpp pipewire gtk4 wlr-randr xwayland-satellite xdg-desktop-portal)

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
    local url="$1" destination="$2"
    if [ -d "$destination/.git" ]; then
        [ -z "$(git -C "$destination" status --porcelain)" ] || die "$destination has local changes; refusing to overwrite them."
        git -C "$destination" pull --ff-only
        git -C "$destination" submodule update --init --recursive
    elif [ -e "$destination" ]; then
        die "$destination exists but is not a Git checkout."
    else
        git clone --recursive "$url" "$destination"
    fi
}

checkout "$UMBRIEL_REPO" "$SOURCE_ROOT/umbriel"
checkout "$PORTAL_REPO" "$SOURCE_ROOT/xdg-desktop-portal-umbriel"

build_install() {
    local source="$1"
    local build="$source/build-nbshell"
    if [ -d "$build" ]; then
        meson setup "$build" "$source" --reconfigure --buildtype=release --prefix="$PREFIX"
    else
        meson setup "$build" "$source" --buildtype=release --prefix="$PREFIX"
    fi
    meson compile -C "$build"
    meson test -C "$build" --print-errorlogs
    meson install -C "$build"
}

apply_umbriel_patch() {
    local source="$SOURCE_ROOT/umbriel"
    [ -f "$UMBRIEL_PATCH" ] || die "Umbriel compatibility patch is missing: $UMBRIEL_PATCH"
    if git -C "$source" apply --check "$UMBRIEL_PATCH" >/dev/null 2>&1; then
        git -C "$source" apply "$UMBRIEL_PATCH"
        return 0
    fi
    if git -C "$source" apply --reverse --check "$UMBRIEL_PATCH" >/dev/null 2>&1; then
        return 1
    fi
    die "The nbshell Umbriel compatibility patch no longer applies; review it before updating."
}

patch_applied=false
if apply_umbriel_patch; then
    patch_applied=true
    trap 'git -C "$SOURCE_ROOT/umbriel" apply --reverse "$UMBRIEL_PATCH"' EXIT
fi
build_install "$SOURCE_ROOT/umbriel"
if $patch_applied; then
    git -C "$SOURCE_ROOT/umbriel" apply --reverse "$UMBRIEL_PATCH"
    trap - EXIT
fi
build_install "$SOURCE_ROOT/xdg-desktop-portal-umbriel"

# Meson uses lib/systemd for a conventional /usr prefix. With a home prefix,
# systemd searches share/systemd instead, so mirror the four upstream units.
mkdir -p "$PREFIX/share/systemd/user"
for unit in "$PREFIX"/lib/systemd/user/umbriel.service \
    "$PREFIX"/lib/systemd/user/umbriel-session.target \
    "$PREFIX"/lib/systemd/user/umbriel-shutdown.target \
    "$PREFIX"/lib/systemd/user/xdg-desktop-portal-umbriel.service; do
    [ -f "$unit" ] && install -m 644 "$unit" "$PREFIX/share/systemd/user/$(basename "$unit")"
done
systemctl --user daemon-reload

# Umbriel supervises its own xwayland-satellite. Arch's separately enabled
# user unit is still needed by Niri, but must not start a second copy inside an
# Umbriel session and race for the X11 display socket.
XWAYLAND_DROPIN="$HOME/.config/systemd/user/xwayland-satellite.service.d/nbshell-umbriel.conf"
mkdir -p "$(dirname "$XWAYLAND_DROPIN")"
printf '%s\n' \
    '[Unit]' \
    'ConditionEnvironment=!XDG_CURRENT_DESKTOP=umbriel' > "$XWAYLAND_DROPIN"
systemctl --user daemon-reload

"$ROOT/install.sh"

# greetd and most other display managers enumerate the system session folder.
# They do not necessarily inherit ~/.local/bin in PATH, so use the absolute
# user-prefix launcher instead of the relative Exec from upstream's desktop file.
SESSION_FILE="$(mktemp "${TMPDIR:-/tmp}/nbshell-umbriel-session.XXXXXX")"
trap 'rm -f -- "$SESSION_FILE"' EXIT
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
    "Native test: log out and choose Umbriel; choose Niri again at any time."
