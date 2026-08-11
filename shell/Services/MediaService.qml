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

    // ── Wo stehen wir? ───────────────────────────────────────────────────
    //
    // MPRIS meldet die Position NICHT von selbst -- sie ist eine Eigenschaft,
    // die man abfragt, sonst stuende die Anzeige still. Quickshell laesst sie
    // mit `positionChanged()` neu einlesen; einmal je Sekunde reicht fuer eine
    // Anzeige, die in Sekunden rechnet.
    //
    // Der Takt laeuft NUR, solange etwas spielt. Pausiert bewegt sich nichts,
    // und ohne Player gibt es nichts zu lesen.
    readonly property real position: player?.position ?? 0
    readonly property real length: player?.length ?? 0
    readonly property bool seekable: player?.canSeek ?? false

    readonly property real volume: player?.volume ?? 0
    readonly property bool volumeSupported: player?.volumeSupported ?? false

    function setVolume(v) {
        if (player?.volumeSupported)
            player.volume = Math.max(0, Math.min(1, v));
    }

    function seek(sekunden) {
        if (player?.canSeek)
            player.position = Math.max(0, Math.min(root.length, sekunden));
    }

    // mm:ss -- Stunden kommen bei Musik nicht vor, und wenn doch, zaehlen die
    // Minuten einfach weiter.
    function zeit(sekunden) {
        if (!(sekunden > 0))
            return "0:00";
        const s = Math.floor(sekunden % 60);
        return Math.floor(sekunden / 60) + ":" + (s < 10 ? "0" : "") + s;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.playing
        onTriggered: root.player?.positionChanged()
    }

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
