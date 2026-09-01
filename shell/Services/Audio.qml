pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Common
import "AudioNodes.js" as AudioNodes

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
    readonly property var sinks: AudioNodes.uniqueSinks(Pipewire.nodes.values, sink)

    // Laufende Wiedergaben. PipeWire stellt sie als Sink-Streams bereit; so
    // braucht nbshell weder pactl-Ausgaben zu parsen noch einen Polling-Takt.
    readonly property var appStreams: Pipewire.nodes.values
        .filter(n => n.audio && n.isSink && n.isStream)
        .sort((a, b) => root.label(a).localeCompare(root.label(b)))

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
        root.tonStatus = "restoring audio …";
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
                    Quickshell.execDetached(["notify-send", "-a", "nbshell", "-u", "normal", "Audio was not restored", String(d.grund)]);
                    quittung.restart();
                    return;
                }
                root.tonStatus = "Audio restored";
                Quickshell.execDetached(["notify-send", "-a", "nbshell", "-t", "2500", "Audio restored", String(d.senke ?? "")]);
                // Die Musik stand ja still, deshalb wurde der Knopf gedrueckt.
                // Aber nur fortsetzen, was PAUSIERT ist -- ein gestoppter
                // Spieler soll nicht von allein losspielen.
                if (MediaService.active && !MediaService.playing)
                    MediaService.playPause();
                quittung.restart();
            }
        }
    }

    Timer {
        id: quittung

        interval: 5000
        onTriggered: root.tonStatus = ""
    }

    // ── Bluetooth-Codec ──────────────────────────────────────────────────
    //
    // Der Gedanke ist von bt.codecs geborgt: am Hoerer entscheidet der Codec
    // ueber den Klang, und man sieht ihm nirgends an, welcher ausgehandelt
    // wurde. Unter PipeWire ist jeder Codec ein Kartenprofil -- Umschalten
    // heisst also Profil wechseln, und der Ton setzt dabei kurz aus.
    //
    // Gelesen wird NUR auf Zuruf: beim Aufklappen des Popouts und nach einem
    // Wechsel. Ein Takt im Hintergrund waere ein `pactl list cards` alle paar
    // Sekunden fuer eine Angabe, die sich zwischen zwei Verbindungen nie
    // aendert.
    readonly property string codecSkript: Qt.resolvedUrl("../scripts/codec.py").toString().replace("file://", "")
    readonly property string routeSkript: Qt.resolvedUrl("../scripts/audio-routes.py").toString().replace("file://", "")

    property string btKarte: ""
    property string btGeraet: ""
    property string btCodec: ""
    property string btBeste: ""
    property bool btTelefonie: false
    property var btCodecs: []

    // Ob ueberhaupt schon einmal gelesen wurde. Ohne das antwortet der erste
    // Aufruf nach dem Start "kein Bluetooth-Tongeraet" -- was nicht stimmt,
    // sondern nur heisst, dass die Antwort noch unterwegs ist.
    property bool btGelesen: false

    readonly property bool btDa: root.btKarte !== ""

    // Laeuft der Hoerer unter Wert? Genau das war hier der Fall: die Buds
    // koennen AAC, standen aber auf SBC.
    readonly property bool btSchlechter: root.btDa && !root.btTelefonie && root.btBeste !== "" && root.btBeste !== root.btAktiv

    property string btAktiv: ""
    property var routes: []
    property var routeSinks: []

    function codecsLesen() {
        if (!codecProc.running)
            codecProc.running = true;
    }

    function routenLesen() {
        if (!routeProc.running)
            routeProc.running = true;
    }

    function cycleRoute(stream) {
        if (!stream || root.routeSinks.length < 2 || routeSet.running)
            return;
        var current = root.routeSinks.findIndex(s => s.name === stream.sink);
        const next = root.routeSinks[(current + 1) % root.routeSinks.length];
        routeSet.command = ["python3", root.routeSkript, "set", String(stream.index), next.name];
        routeSet.running = true;
    }

    function setzeCodec(profil) {
        if (root.btKarte === "" || profil === "")
            return;
        Quickshell.execDetached(["pactl", "set-card-profile", root.btKarte, profil]);
        // PipeWire baut die Verbindung dabei neu auf -- vorher steht die alte
        // Antwort noch da.
        codecNach.restart();
    }

    Timer {
        id: codecNach

        interval: 1200
        onTriggered: root.codecsLesen()
    }

    Process {
        id: codecProc

        command: ["python3", root.codecSkript]

        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try {
                    d = JSON.parse(text);
                } catch (e) {
                    return;
                }
                root.btGelesen = true;
                if (!d.ok) {
                    root.btKarte = "";
                    root.btCodecs = [];
                    root.btCodec = "";
                    return;
                }
                root.btKarte = d.karte ?? "";
                root.btGeraet = d.geraet ?? "";
                root.btCodec = d.codec ?? "";
                root.btAktiv = d.aktiv ?? "";
                root.btBeste = d.beste ?? "";
                root.btTelefonie = d.telefonie ?? false;
                root.btCodecs = d.codecs ?? [];
            }
        }
    }

    Process {
        id: routeProc
        command: ["python3", root.routeSkript, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.routes = data.streams ?? [];
                    root.routeSinks = data.sinks ?? [];
                } catch (e) {
                    root.routes = [];
                    root.routeSinks = [];
                }
            }
        }
    }

    Process {
        id: routeSet
        onExited: routeAfter.restart()
    }

    Timer {
        id: routeAfter
        interval: 350
        onTriggered: root.routenLesen()
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

    function streamVolume(node) {
        return node?.audio ? Math.round(node.audio.volume * 100) : 0;
    }

    function setStreamVolume(node, percent) {
        if (!node?.audio)
            return;
        node.audio.volume = Math.max(0, Math.min(maxVolume, Math.round(percent))) / 100;
    }

    function toggleStreamMute(node) {
        if (node?.audio)
            node.audio.muted = !node.audio.muted;
    }

    // Ohne Beobachter bleiben `audio.volume` und Freunde leer: Pipewire liefert
    // die Daten eines Knotens erst, wenn jemand ihn im Auge behaelt.
    PwObjectTracker {
        // Auch Anwendungsstroeme beobachten, sonst aktualisieren sich deren
        // Regler und Stummschalter erst verspaetet oder gar nicht.
        objects: Pipewire.nodes.values.filter(n => n.audio)
    }
}
