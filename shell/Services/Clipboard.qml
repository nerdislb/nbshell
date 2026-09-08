pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Clipboard ingestion and disk reads are bounded by clipboard-text.py.
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

    readonly property string textScript: Qt.resolvedUrl("../scripts/clipboard-text.py").toString().replace("file://", "")
    property string pendingSave: ""
    property string activeSave: ""

    function persist() {
        pendingSave = JSON.stringify(entries);
        startSave();
    }

    function startSave() {
        if (writer.running || pendingSave === "") return;
        activeSave = pendingSave;
        pendingSave = "";
        writer.stdinEnabled = true;
        writer.running = true;
    }

    function add(text) {
        if (typeof text !== "string" || text.length > 65536 || text.trim() === "") return;
        var rows = [text].concat(entries.filter(e => e !== text)).slice(0, Math.max(1, Math.min(100, keep)));
        while (rows.length && JSON.stringify(rows).length > 262144) rows.pop();
        entries = rows;
        persist();
    }

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
    }

    function remove(text) {
        entries = entries.filter(e => e !== text);
        persist();
    }

    function clear() {
        entries = [];
        images = [];
        persist();
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

    Process {
        id: loader
        running: root.enabled
        command: ["python3", root.textScript, "load", root.statePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.entries = JSON.parse(text || "[]"); }
                catch (e) { root.entries = []; }
                watcher.running = root.enabled;
            }
        }
    }

    Process {
        id: writer
        command: ["python3", root.textScript, "save", root.statePath]
        onStarted: {
            write(root.activeSave);
            stdinEnabled = false;
        }
        onExited: saveAgain.restart()
    }
    Timer { id: saveAgain; interval: 0; onTriggered: root.startSave() }

    Process {
        id: watcher
        command: ["wl-paste", "--type", "text", "--watch", "python3", root.textScript, "capture", String(root.guardSecrets)]
        stdout: SplitParser {
            onRead: line => {
                try { root.add(JSON.parse(line)); }
                catch (e) { console.warn("nbshell/clipboard: invalid entry"); }
            }
        }
    }
    onEnabledChanged: { if (!enabled) watcher.running = false; }

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
