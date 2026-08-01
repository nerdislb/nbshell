#!/usr/bin/env bash
# Listet alle Themes als JSON: Name, Modus, ein paar Farben fuers Vorschau-
# kaestchen und das erste Wallpaper.
#
# Das ist der Teil von omarchy2dms, den nbshell noch braucht. Umrechnen muss
# hier nichts mehr -- die Shell liest `colors.toml` selbst. Uebrig bleibt das
# Suchen: Themes koennen aus drei Quellen kommen, Wallpaper aus zwei.
#
#   nbshell-themes <themes-verzeichnis>
set -euo pipefail

THEME_DIR="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/nbshell/themes}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Wallpaper liegen entweder beim Theme oder im Zwischenspeicher von
# omarchy2dms -- der laedt sie einmal von Omarchy und teilt sie sich mit uns.
wallpaper_dirs() {
    printf '%s\n' "$1/backgrounds" "$DATA_HOME/omarchy2dms/wallpapers/$2" "$DATA_HOME/nbshell/wallpapers/$2"
}

first_wallpaper() {
    local dir name f
    dir="$1"; name="$2"
    while read -r base; do
        [ -d "$base" ] || continue
        for f in "$base"/*.jpg "$base"/*.jpeg "$base"/*.png "$base"/*.webp; do
            [ -f "$f" ] && { printf '%s' "$f"; return 0; }
        done
    done < <(wallpaper_dirs "$dir" "$name")
    printf ''
}

# Einen Wert aus colors.toml holen. Anfuehrungszeichen weg, Kommentar weg.
peek() {
    awk -v key="$2" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            sub(/[[:space:]]*#[^"]*$/, "")
            gsub(/"/, "")
            gsub(/[[:space:]]*$/, "")
            print
            exit
        }' "$1"
}

printf '['
first=1
for dir in "$THEME_DIR"/*/; do
    [ -f "$dir/colors.toml" ] || continue
    name="$(basename "$dir")"
    toml="$dir/colors.toml"
    [ $first -eq 1 ] || printf ','
    first=0
    printf '{"name":"%s","mode":"%s","background":"%s","foreground":"%s","accent":"%s","red":"%s","green":"%s","yellow":"%s","blue":"%s","magenta":"%s","wallpaper":"%s"}' \
        "$name" \
        "$(peek "$toml" mode)" \
        "$(peek "$toml" background)" \
        "$(peek "$toml" foreground)" \
        "$(peek "$toml" accent)" \
        "$(peek "$toml" red)" \
        "$(peek "$toml" green)" \
        "$(peek "$toml" yellow)" \
        "$(peek "$toml" blue)" \
        "$(peek "$toml" magenta)" \
        "$(first_wallpaper "${dir%/}" "$name")"
done
printf ']\n'
