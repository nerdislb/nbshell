pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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
