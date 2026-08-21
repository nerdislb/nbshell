#!/usr/bin/env bash
# Optional gaming setup for Arch Linux. Every mutating action is started by an
# explicit menu choice and confirmed again here in the terminal.
set -euo pipefail

ACTION="${1:-status}"
ITEM="${2:-}"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

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
        xbox-controllers) echo "Xbox Controllers" ;; battlenet) echo Battle.net ;;
        lutris) echo Lutris ;; heroic) echo "Heroic Games Launcher" ;;
        moonlight) echo Moonlight ;; retro-launcher) echo "RetroArch Game Launcher" ;;
        *) echo "$1" ;;
    esac
}

installed() {
    case "$1" in
        steam|retroarch|lutris) have_pkg "$1" ;;
        minecraft) have_pkg minecraft-launcher || have_pkg prismlauncher ;;
        heroic) have_pkg heroic-games-launcher-bin || have_pkg heroic-games-launcher ;;
        geforce-now) have_flatpak com.nvidia.geforcenow ;;
        xbox-cloud) [[ -f "$APP_DIR/nbshell-xbox-cloud.desktop" ]] ;;
        xbox-controllers) have_pkg xpadneo-dkms ;;
        battlenet) [[ -d "$HOME/Games/battlenet" ]] && find "$HOME/Games/battlenet" -mindepth 1 -print -quit | grep -q . ;;
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
        minecraft)
            # Prism is open source and maintained on Arch; it supports Microsoft
            # accounts and avoids depending on Mojang's AUR-only legacy launcher.
            install_packages prismlauncher jre21-openjdk
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
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            flatpak install flathub com.nvidia.geforcenow
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
        battlenet)
            read -r -a gpu <<<"$(gpu_lib32_packages)"
            install_packages lutris wine-staging umu-launcher "${gpu[@]}"
            mkdir -p "$HOME/Games/battlenet"
            note "Lutris will open. Search its Sources or website for the current Battle.net installer."
            command -v lutris >/dev/null && setsid -f lutris lutris:battlenet >/dev/null 2>&1 || true
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
        minecraft) remove_packages minecraft-launcher prismlauncher jre21-openjdk ;;
        lutris) remove_packages lutris wine-staging wine-mono wine-gecko winetricks umu-launcher ;;
        heroic) remove_packages heroic-games-launcher-bin heroic-games-launcher ;;
        moonlight) remove_packages moonlight-qt ;;
        geforce-now) flatpak uninstall com.nvidia.geforcenow ;;
        xbox-cloud) rm -f "$APP_DIR/nbshell-xbox-cloud.desktop" ;;
        xbox-controllers)
            remove_packages xpadneo-dkms
            sudo rm -f /etc/modprobe.d/nbshell-blacklist-xpad.conf /etc/modules-load.d/nbshell-xpadneo.conf
            ;;
        battlenet)
            note "The Battle.net prefix at ~/Games/battlenet contains installed games and is not deleted automatically."
            ask "Delete that complete prefix too?" && rm -rf -- "$HOME/Games/battlenet"
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
    status)
        for ITEM in steam retroarch minecraft geforce-now xbox-cloud xbox-controllers battlenet lutris heroic moonlight; do
            if installed "$ITEM"; then state=installed; else state=available; fi
            printf '%-24s %s\n' "$(label "$ITEM")" "$state"
        done
        ;;
    *) die "Usage: gaming.sh status|install ITEM|remove ITEM|retro-launcher" ;;
esac
