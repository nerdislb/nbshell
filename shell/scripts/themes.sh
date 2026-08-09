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

# Die Palette eines Themes -- in BEIDEN Dialekten.
#
# Omarchys colors.toml gibt es zweimal:
#
#   alt   benannte Schluessel -- red, green, yellow, blue, magenta, mode
#   neu   ANSI-Nummern -- color0 … color15, ohne `mode`
#
# Die mitgelieferten Themes sind der alte Dialekt, frisch geholte fast immer
# der neue. Wer hier nur den alten liest, bekommt bei einem neu installierten
# Theme leere Farbkaestchen -- und das faellt kaum auf, weil Hintergrund und
# Akzent in beiden Dialekten gleich heissen und die Vorschau deshalb nur
# halb falsch aussieht. Die Shell selbst kennt beide seit jeher
# (Common/Theme.qml, `normalize`); die Vorschau musste nachziehen.
#
# Ausgabe: eine Zeile, Felder durch Tabulator getrennt, in der Reihenfolge
# mode bg fg accent red green yellow blue magenta muted dimfg brightfg cyan.
#
# Die letzten vier kamen mit der Vorschau dazu: um eine Leiste im fremden Theme
# zu zeichnen, reichen Hintergrund und Akzent nicht -- es fehlten der Rahmen
# (muted), die gedaempfte Schrift und die helle. Fehlen sie im Theme, faellt
# jede auf etwas zurueck, das es sicher gibt, statt auf Schwarz.
palette() {
    awk '
        # Relative Luminanz nach WCAG -- nur fuer hell/dunkel gebraucht.
        function lum(h,   i, v, s) {
            sub(/^#/, "", h)
            if (length(h) != 6)
                return -1
            s = 0
            for (i = 0; i < 3; i++) {
                v = strtonum("0x" substr(h, 1 + i * 2, 2)) / 255
                v = (v <= 0.03928) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4
                s += v * (i == 0 ? 0.2126 : i == 1 ? 0.7152 : 0.0722)
            }
            return s
        }
        # Erster Schluessel, den es gibt -- benannt vor ANSI.
        function pick(a, b, c) {
            if (K[a] != "") return K[a]
            if (b != "" && K[b] != "") return K[b]
            if (c != "" && K[c] != "") return K[c]
            return ""
        }
        {
            line = $0
            sub(/\r$/, "", line)
            if (line !~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)
                next
            key = line
            sub(/[[:space:]]*=.*$/, "", key)
            gsub(/^[[:space:]]+/, "", key)
            val = line
            sub(/^[^=]*=[[:space:]]*/, "", val)
            # In Anfuehrungszeichen gilt alles darin, sonst blank bis zum
            # Kommentar. Die Raute leitet NUR den Kommentar ein -- jede Farbe
            # faengt selbst mit einer an.
            if (substr(val, 1, 1) == "\"") {
                sub(/^"/, "", val)
                sub(/".*$/, "", val)
            } else {
                sub(/[[:space:]]*#.*$/, "", val)
                gsub(/[[:space:]]+$/, "", val)
            }
            if (!(key in K))
                K[key] = val
        }
        END {
            bg = pick("background")
            mode = pick("mode")
            # Der neue Dialekt schreibt keinen Modus mehr hin -- er steht im
            # Hintergrund.
            if (mode == "" && bg != "") {
                l = lum(bg)
                if (l >= 0)
                    mode = (l > 0.5) ? "light" : "dark"
            }
            fg = pick("foreground")
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", mode, bg, fg, pick("accent", "color4", "blue"), pick("red", "color1"), pick("green", "color2"), pick("yellow", "color3"), pick("blue", "color4"), pick("magenta", "color5"), pick("muted", "color8"), pick("dark_foreground", "color7"), pick("bright_foreground", "color15"), pick("cyan", "color6")
        }
    ' "$1"
}

printf '['
first=1
for dir in "$THEME_DIR"/*/; do
    [ -f "$dir/colors.toml" ] || continue
    name="$(basename "$dir")"
    IFS=$'\t' read -r mode bg fg accent red green yellow blue magenta muted dimfg brightfg cyan < <(palette "$dir/colors.toml")
    # Was das Theme nicht nennt, wird abgeleitet -- eine leere Farbe waere in
    # QML durchsichtig, und die Miniatur haette Loecher.
    [ -n "$muted" ] || muted="$fg"
    [ -n "$dimfg" ] || dimfg="$fg"
    [ -n "$brightfg" ] || brightfg="$fg"
    [ -n "$cyan" ] || cyan="$blue"
    [ $first -eq 1 ] || printf ','
    first=0
    printf '{"name":"%s","mode":"%s","background":"%s","foreground":"%s","accent":"%s","red":"%s","green":"%s","yellow":"%s","blue":"%s","magenta":"%s","muted":"%s","dimForeground":"%s","brightForeground":"%s","cyan":"%s","wallpaper":"%s"}' \
        "$name" "$mode" "$bg" "$fg" "$accent" "$red" "$green" "$yellow" "$blue" "$magenta" \
        "$muted" "$dimfg" "$brightfg" "$cyan" \
        "$(first_wallpaper "${dir%/}" "$name")"
done
printf ']\n'
