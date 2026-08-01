pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Common

// Lautstaerke und Ausgabegeraete.
//
// Quickshell bringt die Pipewire-Anbindung mit; hier steht nur, was die Leiste
// davon braucht. Der Rest ist eine Umrechnung: Pipewire zaehlt von 0 bis 1,
// angezeigt wird in Prozent.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    readonly property bool ready: sink?.audio !== undefined && sink?.audio !== null
    readonly property int volume: ready ? Math.round(sink.audio.volume * 100) : 0
    readonly property bool muted: ready ? sink.audio.muted : false

    readonly property int maxVolume: Config.value("maxVolume", 100)

    // Nur echte Ausgaben, keine Anwendungsstroeme (`isStream`).
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)

    readonly property int micVolume: source?.audio ? Math.round(source.audio.volume * 100) : 0
    readonly property bool micMuted: source?.audio ? source.audio.muted : false

    function label(node) {
        return node?.nickname || node?.description || node?.name || "?";
    }

    function setVolume(percent) {
        if (!ready)
            return 0;
        const clamped = Math.max(0, Math.min(maxVolume, Math.round(percent)));
        sink.audio.volume = clamped / 100;
        return clamped;
    }

    function step(delta) {
        return setVolume(volume + delta);
    }

    function setMuted(value) {
        if (ready)
            sink.audio.muted = value;
    }

    function toggleMute() {
        setMuted(!muted);
        return muted;
    }

    function setMicMuted(value) {
        if (source?.audio)
            source.audio.muted = value;
    }

    // Pipewire merkt sich die Wahl selbst -- `preferredDefaultAudioSink`
    // ueberlebt auch das Ab- und Anstecken.
    function setSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    // Ohne Beobachter bleiben `audio.volume` und Freunde leer: Pipewire liefert
    // die Daten eines Knotens erst, wenn jemand ihn im Auge behaelt.
    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    }
}
