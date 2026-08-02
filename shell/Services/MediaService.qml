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

    // Zwei Schritte statt einem: `player` darf `lastActive` LESEN, aber nicht
    // selbst setzen -- sonst haengt die Bindung an ihrem eigenen Ergebnis
    // ("Binding loop detected"). Gemerkt wird deshalb nur, wer spielt.
    readonly property var playingPlayer: players.find(p => p.isPlaying) ?? null

    readonly property var player: {
        if (playingPlayer)
            return playingPlayer;
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

    onPlayingPlayerChanged: {
        if (playingPlayer)
            lastActive = playingPlayer;
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
