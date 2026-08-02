pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Verfuegbare Systemupdates.
//
// Gesucht wird mit scripts/updates.sh -- ohne root und ohne die Systemdatenbank
// anzufassen (eigene Datenbank unter fakeroot, wie `checkupdates`).
//
// Aktualisiert wird NICHT von der Shell aus, sondern in einem Terminal: es
// fragt nach dem Passwort, will bestaetigt werden und zeigt, was passiert.
// Ein Systemupdate, das im Hintergrund einer Leiste laeuft, waere unheimlich.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/updates.sh").toString().replace("file://", "")

    property var repo: []
    property var aur: []
    property bool checking: false
    property date lastCheck: new Date(0)

    readonly property int count: repo.length + aur.length
    readonly property bool ready: lastCheck.getTime() > 0

    // Alle vier Stunden reicht: Arch veroeffentlicht laufend, aber niemand
    // will alle zehn Minuten einen Datenbankabgleich im Hintergrund.
    readonly property int interval: Config.value("updateInterval", 14400000)
    readonly property bool enabled: Config.value("updates", true)

    function refresh() {
        if (!enabled || checking)
            return;
        checking = true;
        proc.command = ["bash", root.script, "check"];
        proc.running = true;
    }

    // Welcher Helfer genommen wird, sagt das Skript -- so steht die Wahl an
    // einer Stelle.
    readonly property string terminal: Config.value("terminal", "") || Quickshell.env("TERMINAL") || "xterm"

    // IM TERMINAL, nicht im Hintergrund: paru fragt nach dem Passwort und will
    // bestaetigt werden. Ohne Fenster haengt es unsichtbar an der Eingabe.
    // `read` am Ende laesst das Ergebnis stehen, statt das Fenster im Moment
    // des Fertigwerdens zuzuklappen.
    function update() {
        const line = "cmd=$(bash '" + root.script + "' command); $cmd; echo; read -n1 -r -p 'fertig — Taste schliesst das Fenster'";
        Quickshell.execDetached([root.terminal, "-e", "sh", "-c", line]);
    }

    // Nur zum Nachsehen, was beim Aktualisieren liefe.
    function updateCommand() {
        return "cmd=$(bash '" + root.script + "' command); $cmd";
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.repo = data.repo ?? [];
                    root.aur = data.aur ?? [];
                    root.lastCheck = new Date();
                } catch (e) {
                    console.warn("nbshell/updates: Antwort unlesbar —", e);
                }
                root.checking = false;
            }
        }
    }

    Timer {
        interval: root.interval
        running: root.enabled
        repeat: true
        // Beim Start einmal -- aber erst nach einer Minute, damit die Anmeldung
        // nicht mit einem Datenbankabgleich anfaengt.
        triggeredOnStart: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60000
        running: root.enabled
        repeat: false
        onTriggered: root.refresh()
    }
}
