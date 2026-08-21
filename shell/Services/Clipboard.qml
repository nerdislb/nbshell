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
// sonst zerfiele ein mehrzeiliger Text in lauter Einzelmeldungen. Decoding
// stays in JavaScript: Qt's string atob overload is deprecated and behaves
// differently from the browser API for non-ASCII clipboard contents.
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
    readonly property int imageKeep: Config.value("clipboardImageKeep", 20)

    // Nur abschalten, wenn man weiss, was man tut.
    readonly property bool guardSecrets: Config.value("clipboardGuardSecrets", true)

    property var entries: []
    property var images: []

    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/clipboard.json"
    readonly property string imageDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/clipboard-images"
    readonly property string imageScript: Qt.resolvedUrl("../scripts/clipboard-images.py").toString().replace("file://", "")

    function decode(base64) {
        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        const input = String(base64 || "").replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/");
        const bytes = [];
        var bits = 0;
        var value = 0;
        for (var i = 0; i < input.length; i++) {
            if (input[i] === "=") break;
            const digit = alphabet.indexOf(input[i]);
            if (digit < 0) continue;
            value = (value << 6) | digit;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                bytes.push((value >> bits) & 0xff);
            }
        }
        var encoded = "";
        for (var j = 0; j < bytes.length; j++)
            encoded += "%" + bytes[j].toString(16).padStart(2, "0");
        try { return decodeURIComponent(encoded); }
        catch (e) { return bytes.map(b => String.fromCharCode(b)).join(""); }
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
        images = [];
        store.setText("[]");
        Quickshell.execDetached(["python3", imageScript, "clear", imageDir]);
        Quickshell.execDetached(["wl-copy", "--clear"]);
    }

    function imagePath(entry) {
        return "file://" + imageDir + "/" + entry.file;
    }

    function copyImage(entry) {
        Quickshell.execDetached(["python3", imageScript, "copy", imageDir, entry.file]);
    }

    function removeImage(entry) {
        imageRemove.command = ["python3", imageScript, "remove", imageDir, entry.file];
        imageRemove.running = true;
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

    Process {
        id: imageLoader
        running: root.enabled
        command: ["python3", root.imageScript, "list", root.imageDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.images = JSON.parse(text || "[]"); }
                catch (e) { root.images = []; }
            }
        }
    }

    Process {
        id: imageWatcher
        running: root.enabled
        command: ["wl-paste", "--type", "image/png", "--watch", "python3", root.imageScript, "capture", root.imageDir, String(root.imageKeep)]
        stdout: SplitParser {
            onRead: line => {
                try { root.images = JSON.parse(line); }
                catch (e) { console.warn("nbshell/clipboard: Bildindex unlesbar", e); }
            }
        }
    }

    Process {
        id: imageRemove
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.images = JSON.parse(text || "[]"); }
                catch (e) {}
            }
        }
    }
}
