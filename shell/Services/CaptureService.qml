pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Bildschirmaufnahme -- uebernommen aus dem DMS-Plugin `screenCapture`
// (github.com/nerdislb/screen-capture, gleiche Hand, gleiche Lizenz).
//
// Die Auswahl macht **niris eigene Screenshot-Oberflaeche**, nicht slurp: sie
// friert das Bild ein UND kennt die Fenster. Unter niri kommt sonst niemand an
// Fensterkoordinaten -- `niri msg windows` liefert Groessen, aber keine Lage
// auf dem Bildschirm.
//
// Alles nach dem Ausloesen (warten, melden, Editor, OCR, Aufnahme) macht
// capture.sh: das ist Shell-Arbeit und laesst sich so auch auf eine Taste
// legen, ohne die Shell zu fragen.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/capture.sh").toString().replace("file://", "")

    readonly property string shotDir: expand(Config.value("shotDir", "~/Pictures/Screenshots"))
    readonly property string videoDir: expand(Config.value("videoDir", "~/Videos"))
    readonly property string editor: Config.value("captureEditor", "satty")
    readonly property bool autoEdit: Config.value("captureAutoEdit", false)
    readonly property bool notifyOn: Config.value("captureNotify", true)
    readonly property string ocrLangs: Config.value("ocrLangs", "deu+eng")
    readonly property string recAudio: Config.value("recAudio", "off")
    readonly property bool recRegion: Config.value("recRegion", false)

    property bool recording: false

    function expand(path) {
        return String(path).replace(/^~/, Quickshell.env("HOME"));
    }

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
    }

    function run(args) {
        Quickshell.execDetached([root.script].concat(args));
    }

    // Der Zielordner muss stehen, BEVOR niri schreibt -- sonst geht die
    // Aufnahme ins Leere.
    function shoot(kind) {
        const path = shotDir + "/screenshot-" + stamp() + ".png";
        Quickshell.execDetached(["sh", "-c", "mkdir -p " + JSON.stringify(shotDir)]);
        if (!niriShot(kind, path))
            return false;
        run(["post", path, editor, autoEdit ? "1" : "0", notifyOn ? "1" : "0"]);
        return true;
    }

    function ocr() {
        const path = "/tmp/nbshell-ocr-" + Date.now() + ".png";
        if (!niriShot("region", path))
            return false;
        run(["ocr", path, ocrLangs, notifyOn ? "1" : "0"]);
        return true;
    }

    function toggleRecording() {
        if (recording) {
            run(["rec-stop", notifyOn ? "1" : "0"]);
            return "gestoppt";
        }
        Quickshell.execDetached(["sh", "-c", "mkdir -p " + JSON.stringify(videoDir)]);
        run(["rec-start", videoDir, recAudio, recRegion ? "1" : "0"]);
        return "laeuft";
    }

    function editLast() {
        run(["edit-last", shotDir, editor]);
    }

    function openDir() {
        run(["open-dir", shotDir]);
    }

    // `niri msg action` statt IPC von Hand: siehe die Erklaerung in
    // Services/Niri.qml -- ein dauerhaft offener Befehls-Socket funktioniert
    // bei niri nur ein einziges Mal.
    function niriShot(kind, path) {
        if (!Niri.available)
            return false;
        var verb = "screenshot";        // die Auswahl-Oberflaeche
        if (kind === "window")
            verb = "screenshot-window";
        else if (kind === "screen")
            verb = "screenshot-screen";
        Niri.action([verb, "--path", path]);
        return true;
    }

    // Nachsehen statt merken: so stimmt der Zustand auch, wenn die Aufnahme im
    // Terminal gestartet wurde oder die Shell zwischendurch neu geladen hat.
    Process {
        id: probe

        command: ["pgrep", "-x", "wf-recorder"]
        onExited: code => root.recording = (code === 0)
    }

    Timer {
        interval: root.recording ? 1000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!probe.running)
            probe.running = true
    }
}
