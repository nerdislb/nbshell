pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Die Tastenkuerzel von niri.
//
// Heisst `Binds` und nicht `Keys`: `Keys` ist in QML der Name der
// angehaengten Tastatur-Eigenschaft (`Keys.onPressed`). Ein Singleton mit
// diesem Namen waere in jedem Windows mehrdeutig, das Tasten annimmt -- und
// das ist genau das Windows, das diese Liste anzeigt.
//
// Gelesen wird die Konfiguration selbst -- niri gibt seine Bindungen nicht
// heraus, siehe scripts/keys.py. Hier steht nur das Drumherum: einmal lesen,
// merken, und auf Wunsch neu lesen.
//
// Kein Beobachten der Datei: wer seine Kuerzel aendert, laedt niri ohnehin neu
// und macht das Windows danach neu auf. Beim Oeffnen wird gelesen, wenn noch
// nichts da ist; F5 holt es frisch.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/keys.py").toString().replace("file://", "")

    property var list: []
    property bool loading: false
    property string problem: ""

    readonly property bool ready: root.list.length > 0

    // Die Gruppen in der Reihenfolge, in der sie im Windows stehen sollen --
    // erst was man taeglich braucht, dann das Seltene. Alphabetisch waere
    // einfacher und schlechter: "Capture" stuende vor "Applications".
    readonly property var gruppen: ["Applications", "Windows", "Workspaces", "Displays", "Audio and display", "Capture", "Session", "Other"]

    function ensure() {
        if (root.list.length === 0)
            root.load();
    }

    function load() {
        if (root.loading)
            return;
        root.loading = true;
        proc.running = true;
    }

    Process {
        id: proc

        command: ["python3", root.script]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.ok) {
                        root.list = data.binds ?? [];
                        root.problem = "";
                    } else {
                        root.problem = data.grund ?? "unknown";
                    }
                } catch (e) {
                    root.problem = "Antwort unlesbar";
                    console.warn("nbshell/keys: Antwort unlesbar —", e);
                }
                root.loading = false;
            }
        }
    }
}
