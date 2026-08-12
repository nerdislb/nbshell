pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Fehlgeschlagene systemd-Einheiten.
//
// Der Gedanke ist von omarchy-systemd-widget geborgt: das Interessante an
// systemd ist nicht die Liste der 300 laufenden Dienste, sondern die Handvoll,
// die es nicht geschafft hat. Solange nichts kaputt ist, hat dieser Baustein
// deshalb nichts zu sagen -- und sagt auch nichts.
//
// Gefragt wird `systemctl --failed` in beiden Bereichen: die eigenen Dienste
// (der Abgleich der Kalender, der Musikspieler, die Shell selbst) und die des
// Systems. Beides geht ohne root; erst das REPARIEREN braucht Rechte, und
// genau da trennen sich die Wege:
//
//   * eigene Einheit  -> `systemctl --user restart` laeuft sofort durch
//   * System-Einheit  -> im Terminal mit sudo, damit man die Passwortfrage
//                        sieht. Dieselbe Regel wie beim Updater.
//
// Abgefragt wird alle zwei Minuten und beim Aufklappen. Kein 5-Sekunden-Takt:
// eine kaputte Einheit ist kaputt, bis jemand hinsieht -- und ein Prozess alle
// fuenf Sekunden waere derselbe Fehler, der schon bei der Aufnahmeanzeige
// aufgeraeumt werden musste. Zwei Minuten sind der Preis dafuer, dass die Zahl
// auch dann wieder verschwindet, wenn man die Einheit im Terminal repariert:
// systemd meldet uns nichts von sich aus.
Singleton {
    id: root

    readonly property bool enabled: Config.value("units", true)

    // Was systemctl zurueckgibt, ist schon JSON (`--output=json`, seit systemd
    // 246). Kein eigenes Skript, kein awk auf Spaltenbreiten.
    property var userUnits: []
    property var systemUnits: []

    property bool checking: false
    property date lastCheck: new Date(0)

    readonly property var failed: root.userUnits.concat(root.systemUnits)
    readonly property int count: root.failed.length
    readonly property bool ready: root.lastCheck.getTime() > 0

    readonly property string terminal: Config.value("terminal", "") || Quickshell.env("TERMINAL") || "xterm"

    function refresh() {
        if (!root.enabled || root.checking)
            return;
        root.checking = true;
        userProc.running = true;
        systemProc.running = true;
    }

    // Beide Abfragen laufen nebeneinander; fertig ist es, wenn keine mehr
    // laeuft. Sonst stuende `checking` schon auf false, waehrend die zweite
    // Liste noch die alte ist.
    function fertig() {
        root.checking = userProc.running || systemProc.running;
        if (!root.checking)
            root.lastCheck = new Date();
    }

    function lies(text, bereich) {
        try {
            const data = JSON.parse(text);
            if (!Array.isArray(data))
                return [];
            return data.map(u => ({
                        "name": u.unit ?? "?",
                        "bereich": bereich,
                        "zustand": u.sub ?? u.active ?? "",
                        "text": u.description ?? ""
                    }));
        } catch (e) {
            console.warn("nbshell/units: Antwort unlesbar —", e);
            return [];
        }
    }

    // Neu starten. Die eigene Einheit direkt, die des Systems im Terminal --
    // sudo fragt dort nach dem Passwort, und eine Passwortfrage, die unsichtbar
    // in einer Leiste haengt, ist keine.
    function restart(einheit) {
        if (einheit.bereich === "user") {
            Quickshell.execDetached(["systemctl", "--user", "restart", einheit.name]);
            nachfassen.restart();
            return;
        }
        const line = "sudo systemctl restart '" + einheit.name + "'; echo; read -n1 -r -p 'fertig — Taste schliesst das Fenster'";
        Quickshell.execDetached([root.terminal, "-e", "sh", "-c", line]);
        nachfassen.restart();
    }

    // Wegraeumen statt reparieren: manche Einheit ist einmal gescheitert und
    // soll gar nicht wieder laufen. `reset-failed` loescht nur den Vermerk.
    function clear(einheit) {
        if (einheit.bereich === "user") {
            Quickshell.execDetached(["systemctl", "--user", "reset-failed", einheit.name]);
            nachfassen.restart();
            return;
        }
        const line = "sudo systemctl reset-failed '" + einheit.name + "'; echo; read -n1 -r -p 'fertig — Taste schliesst das Fenster'";
        Quickshell.execDetached([root.terminal, "-e", "sh", "-c", line]);
        nachfassen.restart();
    }

    // Das Protokoll im Terminal -- die eigentliche Antwort auf "warum?" steht
    // dort und nicht in einer Leiste.
    function journal(einheit) {
        const cmd = einheit.bereich === "user" ? "journalctl --user -u '" + einheit.name + "' -e" : "journalctl -u '" + einheit.name + "' -e";
        Quickshell.execDetached([root.terminal, "-e", "sh", "-c", cmd]);
    }

    Process {
        id: userProc

        command: ["systemctl", "--user", "list-units", "--failed", "--output=json", "--no-pager"]

        stdout: StdioCollector {
            onStreamFinished: root.userUnits = root.lies(text, "user")
        }

        onRunningChanged: if (!running)
            root.fertig()
    }

    Process {
        id: systemProc

        command: ["systemctl", "list-units", "--failed", "--output=json", "--no-pager"]

        stdout: StdioCollector {
            onStreamFinished: root.systemUnits = root.lies(text, "system")
        }

        onRunningChanged: if (!running)
            root.fertig()
    }

    // Nach einem Eingriff braucht systemd einen Moment, bis der neue Zustand
    // steht -- einmal nachsehen, statt die Zahl stehenzulassen.
    Timer {
        id: nachfassen

        interval: 2000
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: Config.value("unitsInterval", 120000)
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
