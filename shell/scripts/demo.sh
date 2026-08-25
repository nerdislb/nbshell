#!/usr/bin/env bash
# Short, on-demand desktop demos built on nbshell's existing recorder.
set -uo pipefail

RUNTIME="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/nbshell"
CAPTURE="$RUNTIME/scripts/capture.sh"
VIDEO_DIR="${NBSHELL_DEMO_DIR:-$HOME/Videos/nbshell-demos}"

latest() {
    # Exported copies must not become the source of the next export. Keeping
    # one original avoids cumulative scaling and generation loss.
    find "$VIDEO_DIR" -maxdepth 1 -type f -name 'screenrecording-*.mp4' \
        ! -name '*-reddit.mp4' ! -name '*-discord.mp4' ! -name '*-github.mp4' \
        -printf '%T@\t%p\n' 2>/dev/null |
        sort -nr | cut -f2- | head -1
}

start() {
    local area="${1:-region}" audio="${2:-off}" region=1
    case "$area" in
        region) region=1 ;;
        screen) region=0 ;;
        *) echo "Usage: nbshell demo start [region|screen] [off|mic|desktop]" >&2; return 2 ;;
    esac
    case "$audio" in off|mic|desktop) ;; *) echo "Unknown audio source: $audio" >&2; return 2 ;; esac
    mkdir -p "$VIDEO_DIR"
    "$CAPTURE" rec-start "$VIDEO_DIR" "$audio" "$region" -r 60
}

stop() {
    "$CAPTURE" rec-stop 0
    local file
    file="$(latest)"
    if [ -n "$file" ]; then
        notify-send -a nbshell "Demo saved" "$(basename "$file")" -t 3500 >/dev/null 2>&1 || true
        printf '%s\n' "$file"
    fi
}

export_demo() {
    local preset="${1:-reddit}" source output
    source="$(latest)"
    [ -n "$source" ] || { echo "No demo recording found in $VIDEO_DIR" >&2; return 1; }
    command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required for export" >&2; return 127; }
    case "$preset" in
        reddit)
            output="${source%.*}-reddit.mp4"
            ffmpeg -hide_banner -loglevel error -y -i "$source" -vf "scale='min(1920,iw)':-2" -c:v libx264 -preset medium -crf 22 -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 160k "$output"
            ;;
        discord)
            output="${source%.*}-discord.mp4"
            ffmpeg -hide_banner -loglevel error -y -i "$source" -vf "fps=30,scale='min(1280,iw)':-2" -c:v libx264 -preset medium -crf 28 -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 96k "$output"
            ;;
        github)
            output="${source%.*}-github.webm"
            ffmpeg -hide_banner -loglevel error -y -i "$source" -vf "fps=30,scale='min(1280,iw)':-2" -c:v libvpx-vp9 -crf 32 -b:v 0 -an "$output"
            ;;
        *) echo "Unknown preset: $preset (reddit|discord|github)" >&2; return 2 ;;
    esac
    printf '%s\n' "$output"
}

case "${1:-status}" in
    start) shift; start "$@" ;;
    stop) stop ;;
    edit) "$CAPTURE" trim-last "$VIDEO_DIR" ;;
    open) "$CAPTURE" open-dir "$VIDEO_DIR" ;;
    export) shift; export_demo "$@" ;;
    status)
        if "$CAPTURE" rec-active; then echo "recording"; else echo "idle"; fi
        printf 'directory: %s\n' "$VIDEO_DIR"
        [ -n "$(latest)" ] && printf 'latest: %s\n' "$(latest)"
        ;;
    *) echo "Usage: nbshell demo start|stop|edit|open|export [reddit|discord|github]|status" >&2; exit 2 ;;
esac
