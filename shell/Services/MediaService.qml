pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Common

// Medienwiedergabe (MPRIS).
//
// Quickshell bringt die Anbindung mit; hier steht die Auswahl, welcher Player
// gemeint ist, wenn mehrere laufen: der spielende gewinnt, sonst der zuletzt
// benutzte. Ohne diese Regel greifen die Medientasten mal ins Leere, mal in
// den falschen Player.
Singleton {
    id: root

    readonly property var players: Mpris.players?.values ?? []

    property var lastActive: null

    readonly property var player: {
        const playing = players.find(p => p.isPlaying);
        if (playing)
            return playing;
        if (lastActive && players.indexOf(lastActive) >= 0)
            return lastActive;
        return players[0] ?? null;
    }

    readonly property bool active: player !== null
    readonly property bool playing: player?.isPlaying ?? false

    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""

    readonly property string label: {
        if (!active)
            return "";
        const t = title || "unbekannt";
        return artist ? (artist + " — " + t) : t;
    }

    onPlayerChanged: {
        if (player)
            lastActive = player;
    }

    function playPause() {
        if (player?.canTogglePlaying)
            player.togglePlaying();
    }

    function next() {
        if (player?.canGoNext)
            player.next();
    }

    function previous() {
        if (player?.canGoPrevious)
            player.previous();
    }

    function stop() {
        player?.stop();
    }
}
