#!/usr/bin/env bash
# Mittlere Farbe des Wallpaper-Streifens direkt hinter der Bar.
# Nach Omarchys omarchy-bar-text-color, aber die Probe geht an QML zurueck:
# dadurch kann nbshell neben Vorder-/Hintergrund auch seine Akzentrollen auf
# Lesbarkeit pruefen.
set -euo pipefail

position=${1:-top}
bar_size=${2:-}
screen_size=${3:-}
background=${4:-}

fallback() { exit 0; }

[[ $position =~ ^(top|bottom)$ ]] || fallback
[[ $bar_size =~ ^[0-9]+$ ]] || fallback
[[ $screen_size =~ ^([0-9]+)x([0-9]+)$ ]] || fallback
command -v magick >/dev/null 2>&1 || fallback
[[ -f $background ]] || fallback

screen_width=${BASH_REMATCH[1]}
screen_height=${BASH_REMATCH[2]}
((screen_width > 0 && screen_height > 0 && bar_size > 0)) || fallback

crop_y=0
if [[ $position == bottom ]]; then
    crop_y=$((screen_height - bar_size))
    ((crop_y >= 0)) || fallback
fi

pixel=$(magick "$background" -auto-orient \
    -resize "${screen_width}x${screen_height}^" \
    -gravity center -extent "${screen_width}x${screen_height}" \
    -gravity NorthWest -crop "${screen_width}x${bar_size}+0+${crop_y}" +repage \
    -resize '1x1!' -format '#%[hex:p{0,0}]' info:- 2>/dev/null || true)

[[ $pixel =~ ^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$ ]] || fallback
printf '%.7s\n' "$pixel"
