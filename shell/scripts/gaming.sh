#!/usr/bin/env bash
# Optional gaming setup for Arch Linux. Every mutating action is started by an
# explicit menu choice. Native package authentication remains visible when needed.
set -euo pipefail

ACTION="${1:-status}"
ITEM="${2:-}"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

# Minecraft installs natively, using the same progress surface without auto-launch.
if [[ "$ITEM" == "minecraft" && "$ACTION" == "install" ]]; then
    export NBSHELL_GAMING_STORE=minecraft NBSHELL_GAMING_ACTION=install
    exec "$(command -v qs || command -v quickshell)" -p "$(dirname "${BASH_SOURCE[0]}")/../GamingSetup.qml"
fi

# Windows stores use one background worker; native games retain their own setup.
if [[ "$ITEM" =~ ^(battlenet|gog|epic)$ ]]; then
    case "$ACTION" in
        install|launch)
            export NBSHELL_GAMING_STORE="$ITEM" NBSHELL_GAMING_ACTION="$ACTION"
            exec "$(command -v qs || command -v quickshell)" -p "$(dirname "${BASH_SOURCE[0]}")/../GamingSetup.qml"
            ;;
        remove|cancel)
            exec python3 "$(dirname "${BASH_SOURCE[0]}")/gaming_faugus.py" "$ACTION" "$ITEM"
            ;;
    esac
fi

printf '\033]0;nbshell-gaming\007'

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
note() { printf '\033[36m%s\033[0m\n' "$*"; }
ask() {
    local answer
    read -r -p "$1 [y/N] " answer || return 1
    [[ "$answer" =~ ^[yY]$ ]]
}
have_pkg() { pacman -Qq "$1" >/dev/null 2>&1; }
have_flatpak() { command -v flatpak >/dev/null 2>&1 && flatpak info "$1" >/dev/null 2>&1; }

minecraft_instance() {
    local root="${XDG_DATA_HOME:-$HOME/.local/share}/PrismLauncher"
    local selected=""
    if [[ -f "$root/prismlauncher.cfg" ]]; then
        selected="$(sed -n 's/^SelectedInstance=//p' "$root/prismlauncher.cfg" | tail -n 1)"
        [[ -n "$selected" && -f "$root/instances/$selected/instance.cfg" ]] && {
            printf '%s\n' "$selected"
            return 0
        }
    fi
    local cfg
    cfg="$(find "$root/instances" -mindepth 2 -maxdepth 2 -name instance.cfg -print 2>/dev/null | head -n 1)"
    [[ -n "$cfg" ]] || return 1
    basename "$(dirname "$cfg")"
}

write_minecraft_desktop() {
    python3 "$(dirname "${BASH_SOURCE[0]}")/gaming_minecraft.py" desktop
}

launch_minecraft() {
    command -v prismlauncher >/dev/null 2>&1 || die "Install Minecraft from the nbshell Gaming menu first."
    local instance
    instance="$(minecraft_instance 2>/dev/null || true)"
    if [[ -z "$instance" ]]; then
        note "Create or import a Minecraft instance once. Future launches will start it directly."
        exec prismlauncher
    fi
    exec prismlauncher --launch "$instance"
}

aur_helper() {
    if command -v paru >/dev/null 2>&1; then printf paru
    elif command -v yay >/dev/null 2>&1; then printf yay
    else return 1
    fi
}

install_packages() {
    local official=() aur=() pkg helper
    for pkg in "$@"; do
        have_pkg "$pkg" && continue
        if pacman -Si "$pkg" >/dev/null 2>&1; then official+=("$pkg")
        else aur+=("$pkg")
        fi
    done
    ((${#official[@]} == 0)) || sudo pacman -S --needed "${official[@]}"
    if ((${#aur[@]})); then
        helper="$(aur_helper)" || die "An AUR helper is required for: ${aur[*]}. Install paru or yay first."
        "$helper" -S --needed "${aur[@]}"
    fi
}

remove_packages() {
    local installed=() pkg
    for pkg in "$@"; do have_pkg "$pkg" && installed+=("$pkg"); done
    ((${#installed[@]} == 0)) || sudo pacman -Rns "${installed[@]}"
}

gpu_lib32_packages() {
    local found=()
    command -v lspci >/dev/null 2>&1 || { printf '%s\n' ""; return; }
    lspci | grep -qiE '(VGA|3D|Display).*Intel' && found+=(lib32-vulkan-intel)
    lspci | grep -qiE '(VGA|3D|Display).*(AMD|ATI)' && found+=(lib32-vulkan-radeon)
    lspci | grep -qiE '(VGA|3D|Display).*NVIDIA' && found+=(lib32-nvidia-utils)
    printf '%s\n' "${found[*]}"
}

ensure_multilib() {
    pacman -Sl multilib >/dev/null 2>&1 && return 0
    note "Steam and 32-bit graphics drivers require Arch's multilib repository."
    grep -q '^#\[multilib\]$' /etc/pacman.conf 2>/dev/null || \
        die "Enable [multilib] in /etc/pacman.conf, run sudo pacman -Syu, and try again."
    ask "Enable multilib and run a full system upgrade now?" || \
        die "Steam setup stopped without changing pacman.conf."
    sudo cp /etc/pacman.conf /etc/pacman.conf.nbshell-before-multilib
    sudo sed -i '/^#\[multilib\]$/,/^[[:space:]]*$/ s/^#//' /etc/pacman.conf
    sudo pacman -Syu
}

label() {
    case "$1" in
        steam) echo Steam ;; retroarch) echo RetroArch ;; minecraft) echo Minecraft ;;
        geforce-now) echo "NVIDIA GeForce NOW" ;; xbox-cloud) echo "Xbox Cloud Gaming" ;;
        xbox-controllers) echo "Xbox Controllers" ;; battlenet) echo Battle.net ;; gog) echo "GOG Galaxy" ;; epic) echo "Epic Games" ;;
        lutris) echo Lutris ;; heroic) echo "Heroic Games Launcher" ;;
        moonlight) echo Moonlight ;; retro-launcher) echo "RetroArch Game Launcher" ;;
        *) echo "$1" ;;
    esac
}

installed() {
    case "$1" in
        steam|retroarch|lutris) have_pkg "$1" ;;
        minecraft) have_pkg prismlauncher ;;
        heroic) have_pkg heroic-games-launcher-bin || have_pkg heroic-games-launcher ;;
        geforce-now) have_flatpak com.nvidia.geforcenow ;;
        xbox-cloud) [[ -f "$APP_DIR/nbshell-xbox-cloud.desktop" ]] ;;
        xbox-controllers) have_pkg xpadneo-dkms ;;
        battlenet|gog|epic) python3 "$(dirname "${BASH_SOURCE[0]}")/gaming_faugus.py" status "$1" >/dev/null ;;
        moonlight) have_pkg moonlight-qt ;;
        retro-launcher) have_pkg retroarch ;;
        *) return 1 ;;
    esac
}

install_item() {
    local name gpu=()
    name="$(label "$ITEM")"
    installed "$ITEM" && die "$name is already installed."
    note "This will install $name and may request your sudo password."
    ask "Continue?" || { echo "Cancelled."; return; }
    case "$ITEM" in
        steam)
            ensure_multilib
            read -r -a gpu <<<"$(gpu_lib32_packages)"
            install_packages steam "${gpu[@]}"
            ;;
        retroarch)
            install_packages retroarch retroarch-assets-xmb libretro-core-info libretro-database \
                libretro-overlays libretro-shaders-slang libretro-snes9x libretro-mgba \
                libretro-mupen64plus-next libretro-beetle-psx-hw libretro-flycast \
                libretro-ppsspp libretro-mame
            mkdir -p "$HOME/Games/roms" "$HOME/Games/bios"
            ;;
        lutris)
            read -r -a gpu <<<"$(gpu_lib32_packages)"
            install_packages lutris wine-staging wine-mono wine-gecko winetricks umu-launcher "${gpu[@]}"
            ;;
        heroic)
            read -r -a gpu <<<"$(gpu_lib32_packages)"
            install_packages heroic-games-launcher-bin "${gpu[@]}"
            ;;
        moonlight) install_packages moonlight-qt ;;
        geforce-now)
            install_packages flatpak
            flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            flatpak remote-add --user --if-not-exists GeForceNOW https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
            flatpak install --user GeForceNOW com.nvidia.geforcenow
            ;;
        xbox-cloud)
            mkdir -p "$APP_DIR"
            cat >"$APP_DIR/nbshell-xbox-cloud.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Xbox Cloud Gaming
Comment=Play Xbox Cloud Gaming in your browser
Exec=xdg-open https://www.xbox.com/play
Icon=applications-games
Terminal=false
Categories=Game;
EOF
            command -v update-desktop-database >/dev/null && update-desktop-database "$APP_DIR" || true
            ;;
        xbox-controllers)
            install_packages linux-headers xpadneo-dkms
            ask "Disable the conflicting xpad module and load xpadneo automatically?" && {
                printf 'blacklist xpad\n' | sudo tee /etc/modprobe.d/nbshell-blacklist-xpad.conf >/dev/null
                printf 'hid_xpadneo\n' | sudo tee /etc/modules-load.d/nbshell-xpadneo.conf >/dev/null
                sudo modprobe hid_xpadneo 2>/dev/null || true
            }
            ;;
        *) die "Unknown gaming item: $ITEM" ;;
    esac
    note "$name setup finished."
}

remove_item() {
    local name
    name="$(label "$ITEM")"
    installed "$ITEM" || die "$name is not installed by a known method."
    note "This removes $name. Personal game data is kept unless stated otherwise."
    ask "Continue?" || { echo "Cancelled."; return; }
    case "$ITEM" in
        steam) remove_packages steam ;;
        retroarch) remove_packages retroarch retroarch-assets-xmb libretro-core-info libretro-database libretro-overlays libretro-shaders-slang ;;
        minecraft)
            remove_packages minecraft-launcher prismlauncher jre21-openjdk
            rm -f -- "$APP_DIR/nbshell-minecraft.desktop"
            command -v update-desktop-database >/dev/null && update-desktop-database "$APP_DIR" || true
            ;;
        lutris) remove_packages lutris wine-staging wine-mono wine-gecko winetricks umu-launcher ;;
        heroic) remove_packages heroic-games-launcher-bin heroic-games-launcher ;;
        moonlight) remove_packages moonlight-qt ;;
        geforce-now) flatpak uninstall com.nvidia.geforcenow ;;
        xbox-cloud) rm -f "$APP_DIR/nbshell-xbox-cloud.desktop" ;;
        xbox-controllers)
            remove_packages xpadneo-dkms
            sudo rm -f /etc/modprobe.d/nbshell-blacklist-xpad.conf /etc/modules-load.d/nbshell-xpadneo.conf
            ;;
        *) die "Unknown gaming item: $ITEM" ;;
    esac
    note "$name removal finished."
}

retro_launcher() {
    installed retroarch || die "Install RetroArch first."
    local rom core name desktop
    read -e -r -p "ROM path: " rom
    [[ -f "$rom" ]] || die "ROM not found: $rom"
    read -e -r -p "Core path (for example /usr/lib/libretro/snes9x_libretro.so): " core
    [[ -f "$core" ]] || die "Core not found: $core"
    read -r -p "Launcher name: " name
    [[ -n "$name" ]] || die "A name is required."
    desktop="$(printf '%s' "$name" | tr -cs '[:alnum:]._' '-').desktop"
    mkdir -p "$APP_DIR"
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=retroarch -L %q %q\nIcon=retroarch\nTerminal=false\nCategories=Game;\n' \
        "$name" "$core" "$rom" >"$APP_DIR/nbshell-retro-$desktop"
    command -v update-desktop-database >/dev/null && update-desktop-database "$APP_DIR" || true
    note "Launcher created: $name"
}

case "$ACTION" in
    install) [[ -n "$ITEM" ]] || die "Missing item."; install_item ;;
    remove) [[ -n "$ITEM" ]] || die "Missing item."; remove_item ;;
    retro-launcher) retro_launcher ;;
    desktop)
        if [[ "$ITEM" == "battlenet" ]]; then
            exec python3 "$(dirname "${BASH_SOURCE[0]}")/battlenet.py" register
        fi
        [[ "$ITEM" == "minecraft" ]] || die "Desktop launcher is only available for Minecraft."
        installed minecraft || die "Install Minecraft first."
        write_minecraft_desktop
        note "Minecraft app launcher created."
        ;;
    launch)
        if [[ "$ITEM" == "battlenet" ]]; then
            exec python3 "$(dirname "${BASH_SOURCE[0]}")/battlenet.py" launch
        fi
        [[ "$ITEM" == "minecraft" ]] || die "Direct launch is only available for Minecraft."
        launch_minecraft
        ;;
    status)
        for ITEM in steam retroarch minecraft geforce-now xbox-cloud xbox-controllers battlenet gog epic lutris heroic moonlight; do
            if installed "$ITEM"; then state=installed; else state=available; fi
            printf '%-24s %s\n' "$(label "$ITEM")" "$state"
        done
        ;;
    *) die "Usage: gaming.sh status|install ITEM|remove ITEM|launch minecraft|retro-launcher" ;;
esac
