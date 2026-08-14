#!/usr/bin/env bash
# KDE-Connect-Bruecke fuer nbshell.
#
#   kdeconnect.sh discover [--refresh]   Geraete + Zustand, ein TSV-Satz je Geraet
#   kdeconnect.sh pick-file              Dateiauswahl, gibt den Pfad auf stdout
#
# Zustand kommt ueber gdbus (KDE-Connect-D-Bus-API), nicht ueber kdeconnect-cli:
# nur so gibt es Akku, Ladezustand und Mobilfunk in einem Rutsch. Aktionen
# laufen im Service direkt ueber kdeconnect-cli.
#
# discover-Teil nach Vorbild von jitendradara12/omaconnect (MIT), portiert.
set -uo pipefail

base=/modules/kdeconnect

discover() {
    for c in gdbus sed grep tr; do command -v "$c" >/dev/null 2>&1 || exit 127; done

    gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner org.kde.kdeconnect \
        | grep -q '(true,)' || exit 69

    if [[ "${1:-}" == "--refresh" || "${1:-}" == "-r" ]]; then
        gdbus call --session --dest org.kde.kdeconnect --object-path /modules/kdeconnect \
            --method org.kde.kdeconnect.daemon.forceOnNetworkChange >/dev/null 2>&1 || true
    fi

    property() {
        local path=$1 interface=$2 name=$3 reply
        reply=$(gdbus call --session --dest org.kde.kdeconnect \
            --object-path "$path" --method org.freedesktop.DBus.Properties.Get \
            "$interface" "$name" 2>/dev/null) || reply=""
        printf '%s\n' "$reply"
    }

    value() {
        printf '%s' "$1" | sed -E "s/^\((true|false),\)$/\1/; s/^\(<('([^']|\\\\')*'|[^>]+)>.*$/\1/; s/^<'(.*)'>,?$/\1/; s/^<([^>]*)>,?$/\1/; s/^'(.*)'$/\1/"
    }

    local ids entries
    ids=$(gdbus call --session --dest org.kde.kdeconnect --object-path "$base" \
        --method org.kde.kdeconnect.daemon.devices false false) || exit 69
    entries=$(printf '%s' "$ids" | sed -E 's/.*\[//; s/\].*//' | tr ',' '\n' \
        | sed -nE "s/^[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\1/p")
    [[ -n "$entries" || "$ids" =~ \(\[[[:space:]]*\],[[:space:]]*\) ]] || exit 70

    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        local path=$entry id name type paired reachable supported plugins
        [[ "$path" == /* ]] || path="$base/devices/$entry"
        id=${path##*/}
        name=$(value "$(property "$path" org.kde.kdeconnect.device name)") || exit 69
        type=$(value "$(property "$path" org.kde.kdeconnect.device type)") || exit 69
        paired=$(value "$(property "$path" org.kde.kdeconnect.device isPaired)") || exit 69
        reachable=$(value "$(property "$path" org.kde.kdeconnect.device isReachable)") || exit 69
        supported=$(property "$path" org.kde.kdeconnect.device supportedPlugins) || exit 69
        plugins=
        for plugin in kdeconnect_battery kdeconnect_ping kdeconnect_share kdeconnect_runcommand kdeconnect_findmyphone kdeconnect_clipboard kdeconnect_connectivity_report kdeconnect_sms; do
            [[ "$supported" == *"'$plugin'"* || "$supported" == *"<$plugin>"* ]] && plugins="${plugins:+$plugins,}$plugin"
        done

        local charge=-1 charging=false
        if [[ "$plugins" == *kdeconnect_battery* ]]; then
            local cr; cr=$(value "$(property "$path/battery" org.kde.kdeconnect.device.battery charge)") || cr=""
            [[ "$cr" =~ ^[0-9]+$ ]] && charge=$cr
            local gr; gr=$(value "$(property "$path/battery" org.kde.kdeconnect.device.battery isCharging)") || gr=false
            [[ "$gr" == true ]] && charging=true
        fi
        local net_type= net_strength=-1
        if [[ "$plugins" == *kdeconnect_connectivity_report* ]]; then
            local tr sr
            tr=$(value "$(property "$path/connectivity_report" org.kde.kdeconnect.device.connectivity_report cellularNetworkType)") || tr=""
            sr=$(value "$(property "$path/connectivity_report" org.kde.kdeconnect.device.connectivity_report cellularNetworkStrength)") || sr=""
            [[ -n "$tr" && "$tr" != "null" ]] && net_type=$tr
            [[ "$sr" =~ ^[0-9]+$ ]] && net_strength=$sr
        fi
        printf 'DEVICE\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$id" "$name" "$type" "$paired" "$reachable" "$charge" "$charging" "$plugins" "$net_type" "$net_strength"
    done <<< "$entries"
}

pick_file() {
    # Portabler Dateidialog: zenity, sonst kdialog. Gibt genau den Pfad aus.
    if command -v zenity >/dev/null 2>&1; then
        zenity --file-selection --title="Datei an das Handy senden" 2>/dev/null
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --getopenfilename "$HOME" 2>/dev/null
    else
        echo "ERR: kein Dateidialog (zenity oder kdialog installieren)" >&2
        exit 127
    fi
}

case "${1:-}" in
    discover) shift; discover "$@" ;;
    pick-file) pick_file ;;
    *) echo "kdeconnect.sh discover|pick-file" >&2; exit 2 ;;
esac
