pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// CPU- und Speicherlast, direkt aus /proc gelesen.
//
// Kein Hilfsprogramm und kein Dienst dazwischen: /proc/stat und /proc/meminfo
// stehen ohnehin da, und eine Zeile davon zu lesen kostet nichts. Die CPU-Last
// ergibt sich aus der Differenz zweier Messungen -- der erste Wert nach dem
// Start ist deshalb immer 0.
Singleton {
    id: root

    property int cpuPercent: 0
    property int memPercent: 0
    property real memUsedGb: 0
    property real memTotalGb: 0

    property var _prev: null

    // ── Einzelheiten fuers Popout ─────────────────────────────────────────
    //
    // Temperaturen, Luefter, Kerne, Platte -- alles, was mehr Arbeit macht als
    // eine Zeile aus /proc zu lesen. Deshalb laeuft es NUR, solange das Popout
    // offen ist: `detailWanted` schaltet den Zeitgeber.
    //
    // Die Grafikkarte wird noch zurueckhaltender gefragt. `nvidia-smi` weckt
    // sie, und auf einem Optimus-Notebook kostet ein Aufruf alle zwei Sekunden
    // Laufzeit. `withGpu` ist deshalb eine eigene Entscheidung.
    property bool detailWanted: false
    readonly property bool withGpu: Config.value("sysGpu", true)

    property var detail: ({})
    readonly property bool hasDetail: detail.ok === true

    readonly property string script: Qt.resolvedUrl("../scripts/sysinfo.sh").toString().replace("file://", "")

    function refreshDetail() {
        if (detailProc.running)
            return;
        detailProc.command = ["bash", root.script, "detail", root.withGpu ? "gpu" : ""];
        detailProc.running = true;
    }

    // Laufzeit als "3 T 4 h" -- Sekunden interessieren hier niemanden.
    function uptimeText(seconds) {
        const d = Math.floor(seconds / 86400);
        const h = Math.floor((seconds % 86400) / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (d > 0)
            return d + " T " + h + " h";
        if (h > 0)
            return h + " h " + m + " min";
        return m + " min";
    }

    // Farbe nach Temperatur. Die Schwellen sind fuer ein Notebook gewaehlt:
    // 80 Grad unter Last ist normal, 90 ist es nicht mehr.
    function tempColor(value) {
        if (value >= 90)
            return Theme.red;
        if (value >= 80)
            return Theme.yellow;
        return Theme.fg;
    }

    Process {
        id: detailProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.detail = JSON.parse(text);
                } catch (e) {
                    console.warn("nbshell/sys: Antwort unlesbar —", e);
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: root.detailWanted
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshDetail()
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
        }
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const line = text().split("\n")[0];
            const parts = line.trim().split(/\s+/).slice(1).map(Number);
            if (parts.length < 4)
                return;
            const idle = parts[3] + (parts[4] ?? 0);
            const total = parts.reduce((a, b) => a + b, 0);
            if (root._prev) {
                const dTotal = total - root._prev.total;
                const dIdle = idle - root._prev.idle;
                if (dTotal > 0)
                    root.cpuPercent = Math.round(100 * (dTotal - dIdle) / dTotal);
            }
            root._prev = {
                "total": total,
                "idle": idle
            };
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const values = ({});
            const lines = text().split("\n");
            for (var i = 0; i < lines.length; i++) {
                const m = lines[i].match(/^(\w+):\s+(\d+)/);
                if (m)
                    values[m[1]] = parseInt(m[2], 10);
            }
            const total = values.MemTotal ?? 0;
            // MemAvailable ist die ehrliche Zahl: MemFree zaehlt Puffer und
            // Cache als belegt und meldet dauerhaft fast volle Speicher.
            const available = values.MemAvailable ?? values.MemFree ?? 0;
            if (total <= 0)
                return;
            root.memTotalGb = total / 1048576;
            root.memUsedGb = (total - available) / 1048576;
            root.memPercent = Math.round(100 * (total - available) / total);
        }
    }
}
