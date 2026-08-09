pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Zwischenablage mit Verlauf.
//
// Kein `cliphist` und kein weiterer Dienst: `wl-paste --watch` meldet jede
// Aenderung, und der Verlauf liegt als JSON in ~/.local/state. wl-clipboard
// ist ohnehin da, sobald man unter Wayland etwas kopieren will.
//
// Der Wachhund schickt jeden Eintrag base64-kodiert und in EINER Zeile --
// sonst zerfiele ein mehrzeiliger Text in lauter Einzelmeldungen. Zurueck
// kommt er ueber den Umweg ueber `escape`, weil Qt.atob byteweise dekodiert
// und Umlaute sonst zerbroeseln.
//
// Passwoerter kommen hier NICHT an: wer ein Geheimnis in die Zwischenablage
// legt, haengt dem Angebot den Mime-Typ `x-kde-passwordManagerHint` an
// (KeePassXC, 1Password, Bitwarden, Vaultwarden-Clients, gnome-keyring). Der
// Wachhund fragt die Typen des laufenden Angebots ab und schweigt dann --
// sonst laege jedes kopierte Passwort im Klartext in ~/.local/state, und zwar
// dauerhaft, waehrend es in der echten Zwischenablage nach Sekunden verfaellt.
Singleton {
    id: root

    readonly property bool enabled: Config.value("clipboard", true)
    readonly property int keep: Config.value("clipboardKeep", 50)

    // Nur abschalten, wenn man weiss, was man tut.
    readonly property bool guardSecrets: Config.value("clipboardGuardSecrets", true)

    property var entries: []

    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/clipboard.json"

    function decode(base64) {
        try {
            return decodeURIComponent(escape(Qt.atob(base64)));
        } catch (e) {
            return Qt.atob(base64);
        }
    }

    function add(text) {
        if (!text || text.trim() === "")
            return;
        // Dasselbe zweimal hintereinander ist kein zweiter Eintrag -- es
        // wandert nur nach oben.
        const rest = entries.filter(e => e !== text);
        entries = [text].concat(rest).slice(0, keep);
        store.setText(JSON.stringify(entries));
    }

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    function remove(text) {
        entries = entries.filter(e => e !== text);
        store.setText(JSON.stringify(entries));
    }

    function clear() {
        entries = [];
        store.setText("[]");
        Quickshell.execDetached(["wl-copy", "--clear"]);
    }

    // Fuer die Anzeige: eine Zeile, sichtbare Zeilenumbrueche.
    function preview(text, width) {
        const flat = String(text).replace(/\s+/g, " ").trim();
        return flat.length > width ? (flat.substring(0, width - 1) + "…") : flat;
    }

    FileView {
        id: store

        path: root.statePath
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                root.entries = JSON.parse(text() || "[]");
            } catch (e) {
                root.entries = [];
            }
        }
        onLoadFailed: root.entries = []
    }

    // Erst lesen, dann pruefen, dann erst weitergeben: `wl-paste --watch`
    // schiebt den Inhalt in die Standardeingabe des Befehls: wer sie nicht
    // leert und einfach aussteigt, schickt dem Wachhund ein SIGPIPE. Deshalb
    // wird immer gelesen und nur die Ausgabe unterdrueckt.
    readonly property string watchCommand: {
        const read = "data=$(base64 -w0)";
        const guard = root.guardSecrets ? "wl-paste --list-types 2>/dev/null | grep -qi passwordmanagerhint && exit 0" : ":";
        return "wl-paste --type text --watch sh -c '" + read + "; " + guard + "; printf \"%s\\n\" \"$data\"'";
    }

    Process {
        id: watcher

        running: root.enabled
        command: ["sh", "-c", root.watchCommand]

        stdout: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root.add(root.decode(line.trim()));
            }
        }
    }
}
