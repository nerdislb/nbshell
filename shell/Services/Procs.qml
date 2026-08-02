pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Prozessliste.
//
// Gelesen mit `ps` -- es steht auf jedem System, kennt die Prozentwerte schon
// und spart das Herumrechnen auf /proc. Abgefragt wird NUR, solange die Liste
// offen ist: ein Zaehler, der im Hintergrund alle zwei Sekunden ein `ps`
// startet, waere reine Verschwendung.
Singleton {
    id: root

    property var list: []
    property string filter: ""
    property string sort: "cpu"

    readonly property var shown: {
        const needle = filter.trim().toLowerCase();
        const filtered = needle === "" ? list : list.filter(p => p.name.toLowerCase().indexOf(needle) >= 0 || String(p.pid).indexOf(needle) >= 0);
        const sorted = filtered.slice();
        if (sort === "mem")
            sorted.sort((a, b) => b.mem - a.mem);
        else if (sort === "name")
            sorted.sort((a, b) => a.name.localeCompare(b.name));
        else
            sorted.sort((a, b) => b.cpu - a.cpu);
        return sorted.slice(0, 60);
    }

    function refresh() {
        proc.running = true;
    }

    function toggleSort() {
        sort = sort === "cpu" ? "mem" : (sort === "mem" ? "name" : "cpu");
    }

    // SIGTERM zuerst -- ein Programm darf sich verabschieden. Erst `hart`
    // schickt SIGKILL.
    function kill(pid, hard) {
        Quickshell.execDetached(["kill", hard ? "-9" : "-15", String(pid)]);
        // Kurz warten, dann neu lesen: sofort danach steht der Prozess noch da.
        refreshTimer.restart();
    }

    // Einmal beim Start, damit `nbshell procs top` sofort etwas sagen kann --
    // danach nur noch, solange die Liste offen ist.
    Component.onCompleted: refresh()

    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        interval: 2000
        repeat: true
        running: Runtime.procsOpen
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc

        command: ["ps", "-eo", "pid,pcpu,pmem,rss,comm", "--sort=-pcpu"]

        stdout: StdioCollector {
            onStreamFinished: {
                const rows = [];
                const lines = text.split("\n");
                // Zeile 0 ist die Ueberschrift.
                for (var i = 1; i < lines.length; i++) {
                    const parts = lines[i].trim().split(/\s+/);
                    if (parts.length < 5)
                        continue;
                    rows.push({
                        "pid": parseInt(parts[0], 10),
                        "cpu": parseFloat(parts[1]),
                        "mem": parseFloat(parts[2]),
                        "rss": parseInt(parts[3], 10),
                        // Der Name kann Leerzeichen enthalten -- der Rest der
                        // Zeile gehoert dazu.
                        "name": parts.slice(4).join(" ")
                    });
                }
                root.list = rows;
            }
        }
    }
}
