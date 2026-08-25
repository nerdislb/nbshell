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
    property string pendingAction: ""

    // CaptureMenu is lazy-loaded. Closing it destroys the menu immediately,
    // so delayed work must live in this always-loaded service rather than in
    // a Timer owned by the menu itself.
    function schedule(action) {
        pendingAction = action;
        actionDelay.restart();
    }

    function runAction(action) {
        switch (action) {
        case "screen": shoot("screen"); break;
        case "region": shoot("region"); break;
        case "ocr": ocr(); break;
        case "qr": qr(); break;
        case "dictate": dictate(); break;
        case "record": toggleRecording(); break;
        case "stream": openStreamingStudio(); break;
        case "trim": trimLastRecording(); break;
        case "edit": editLast(); break;
        case "open": openDir(); break;
        }
    }

    Timer {
        id: actionDelay
        interval: 250
        onTriggered: {
            const action = root.pendingAction;
            root.pendingAction = "";
            root.runAction(action);
        }
    }

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
        if (!compositorShot(kind, path))
            return false;
        run(["post", path, editor, autoEdit ? "1" : "0", notifyOn ? "1" : "0"]);
        return true;
    }

    function shootWindow(windowId) {
        const path = shotDir + "/screenshot-" + stamp() + ".png";
        Quickshell.execDetached(["sh", "-c", "mkdir -p " + JSON.stringify(shotDir)]);
        if (!Compositor.available)
            return false;
        if (Compositor.isNiri) {
            Compositor.action(["screenshot-window", "--id", String(windowId), "--path", path]);
        } else {
            const win = Compositor.windows.find(candidate => String(candidate.id) === String(windowId));
            if (!win)
                return false;
            run(["shot", "window", path, String(win.x) + "," + String(win.y) + " " + String(win.w) + "x" + String(win.h)]);
        }
        run(["post", path, editor, autoEdit ? "1" : "0", notifyOn ? "1" : "0"]);
        return true;
    }

    function ocr() {
        const path = "/tmp/nbshell-ocr-" + Date.now() + ".png";
        if (!compositorShot("region", path))
            return false;
        run(["ocr", path, ocrLangs, notifyOn ? "1" : "0"]);
        return true;
    }

    function qr() {
        const path = "/tmp/nbshell-qr-" + Date.now() + ".png";
        if (!compositorShot("region", path))
            return false;
        run(["qr", path, notifyOn ? "1" : "0"]);
        return true;
    }

    function toggleRecording() {
        if (recording) {
            run(["rec-stop", notifyOn ? "1" : "0"]);
            return "gestoppt";
        }
        Quickshell.execDetached(["sh", "-c", "mkdir -p " + JSON.stringify(videoDir)]);
        run(["rec-start", videoDir, recAudio, recRegion ? "1" : "0"]);
        return "running";
    }

    function editLast() {
        run(["edit-last", shotDir, editor]);
    }

    function trimLastRecording() {
        run(["trim-last", videoDir]);
    }

    function openDir() {
        run(["open-dir", shotDir]);
    }

    function openStreamingStudio() {
        Quickshell.execDetached([
            "sh", "-lc",
            "command -v obs >/dev/null 2>&1 && exec obs --profile 'TikTok Live' --collection TikTok_Live || notify-send -u critical 'nbshell' 'OBS Studio is not installed.'"
        ]);
    }

    function dictate() {
        Quickshell.execDetached([
            "sh", "-lc",
            "command -v voxtype >/dev/null 2>&1 && exec voxtype record toggle || notify-send 'Dictation is not installed' 'Install the optional voxtype-bin package.'"
        ]);
    }

    // `niri msg action` statt IPC von Hand: siehe die Erklaerung in
    // The compositor service owns command transport; callers only select the
    // semantic capture action here.
    function compositorShot(kind, path) {
        if (!Compositor.available)
            return false;
        if (Compositor.isUmbriel) {
            run(["shot", kind, path]);
            return true;
        }
        var verb = "screenshot";        // die Auswahl-Oberflaeche
        if (kind === "window")
            verb = "screenshot-window";
        else if (kind === "screen")
            verb = "screenshot-screen";
        Compositor.action([verb, "--path", path]);
        return true;
    }

    // ── Laeuft gerade eine Aufnahme? ─────────────────────────────────────
    //
    // Frueher stand hier ein Timer, der alle fuenf Sekunden ein `pgrep`
    // gestartet hat -- rund 17.000 Prozesse am Tag, um in aller Regel "nein"
    // zu hoeren. Dabei fuehrt capture.sh selbst Buch: es legt beim Start eine
    // Datei an (`rec-start`) und raeumt sie beim Stoppen wieder weg. Genau
    // diese Datei wird jetzt beobachtet.
    //
    // Der Test oben hat bestaetigt, dass eine FileView auch das ANLEGEN eines
    // bis dahin fehlenden Pfades meldet, nicht nur Aenderungen an einer
    // bestehenden Datei. Damit gilt: Datei da = Aufnahme running. Ohne Timer,
    // ohne Verzoegerung, und auch dann richtig, wenn capture.sh im Terminal
    // gestartet wurde oder die Shell zwischendurch neu geladen hat -- beim
    // Start wird der Pfad einmal gelesen.
    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/screen-capture-recording"

    FileView {
        id: recState

        path: root.stateFile
        watchChanges: true
        printErrors: false

        onFileChanged: recState.reload()
        onLoaded: root.recording = true
        onLoadFailed: root.recording = false
    }

    // Ein Rekorder kann auch abstuerzen -- dann bleibt die Datei liegen und die
    // Leiste zeigte ewig einen roten Punkt. Dagegen wird nachgesehen, aber NUR
    // waehrend einer Aufnahme: im Ruhezustand running hier nichts.
    Process {
        id: probe

        command: ["pgrep", "-x", "wf-recorder"]
        onExited: code => {
            if (code === 0 || !root.recording)
                return;
            // Verwaist: erst die Karteileiche wegraeumen, dann abschalten.
            Quickshell.execDetached(["rm", "-f", root.stateFile]);
            root.recording = false;
        }
    }

    Timer {
        interval: 15000
        running: root.recording
        repeat: true
        onTriggered: if (!probe.running)
            probe.running = true
    }
}
