pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
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

    // ── Ton zurueckholen ─────────────────────────────────────────────────
    //
    // Bluetooth-Hoerer mit Multipoint wandern beim Anruf ans Telefon und
    // kommen nicht von selbst zurueck -- Googles „Audio Switch" schaltet nur
    // zwischen Geraeten desselben Kontos, ein Linux-Laptop ist dort nicht
    // dabei. Die Arbeit macht scripts/ton.sh; hier steht nur, wann.
    readonly property string tonSkript: Qt.resolvedUrl("../scripts/ton.sh").toString().replace("file://", "")

    property string tonStatus: ""
    property bool tonLaeuft: false

    function tonZurueck() {
        if (root.tonLaeuft)
            return;
        root.tonLaeuft = true;
        root.tonStatus = "hole den Ton zurück …";
        holer.command = ["bash", root.tonSkript];
        holer.running = true;
    }

    Process {
        id: holer

        stdout: StdioCollector {
            onStreamFinished: {
                root.tonLaeuft = false;
                let d = null;
                try {
                    d = JSON.parse(text);
                } catch (e) {
                    root.tonStatus = "Antwort unlesbar";
                    quittung.restart();
                    return;
                }
                if (!d.ok) {
                    root.tonStatus = String(d.grund);
                    // Gemeldet wird per Benachrichtigung, nicht still in einer
                    // Eigenschaft: der Befehl kommt aus der Palette oder vom
                    // Terminal, und beide sind weg, bevor die Antwort da ist.
                    // Ein Fehlschlag, den niemand sieht, ist derselbe wie
                    // keiner -- man drueckt noch dreimal und wundert sich.
                    Quickshell.execDetached(["notify-send", "-a", "nbshell", "-u", "normal", "Ton kam nicht zurück", String(d.grund)]);
                    quittung.restart();
                    return;
                }
                root.tonStatus = "Ton ist wieder da";
                Quickshell.execDetached(["notify-send", "-a", "nbshell", "-t", "2500", "Ton ist wieder da", String(d.senke ?? "")]);
                // Die Musik stand ja still, deshalb wurde der Knopf gedrueckt.
                // Aber nur fortsetzen, was PAUSIERT ist -- ein gestoppter
                // Spieler soll nicht von allein losspielen.
                if (Music.spieler && !Music.spielt && Music.queue.length > 0)
                    Music.playPause();
                quittung.restart();
            }
        }
    }

    Timer {
        id: quittung

        interval: 5000
        onTriggered: root.tonStatus = ""
    }

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
