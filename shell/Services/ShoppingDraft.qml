pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string file: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/shopping-list-draft.txt"
    readonly property string sendScript: Qt.resolvedUrl("../scripts/shopping-list-send.py").toString().replace("file://", "")

    property string draft: ""
    property bool loaded: false
    readonly property bool sending: sendProc.running
    property string statusText: "Draft saved locally"
    property bool statusError: false

    signal sendStarted()
    signal sendFinished(bool success, string message)

    function setStatus(message, error) {
        root.statusText = String(message || "");
        root.statusError = error === true;
    }

    function update(value) {
        const next = String(value || "");
        if (next === root.draft)
            return;
        root.draft = next;
        saveTimer.restart();
        if (!root.sending)
            setStatus(next.trim() === "" ? "Start with an item, a sentence, or a pasted list" : "Draft saved locally", false);
    }

    function clear(message) {
        saveTimer.stop();
        root.draft = "";
        store.setText("");
        if (message !== undefined)
            setStatus(message, false);
    }

    function send(target, message) {
        if (root.sending || String(message || "").trim() === "")
            return false;
        setStatus("Sending to “" + target + "”…", false);
        root.sendStarted();
        sendProc.pendingMessage = String(message);
        sendProc.stdinEnabled = true;
        sendProc.command = [
            "python3", root.sendScript,
            "--to", String(target)
        ];
        sendProc.running = true;
        return true;
    }

    function finishSend(code) {
        let payload = null;
        try {
            payload = JSON.parse(String(sendOut.text || "{}"));
        } catch (error) {
            payload = null;
        }
        const ok = code === 0 && payload && payload.success === true;
        const message = payload && payload.message
            ? String(payload.message)
            : (ok ? "Shopping list sent" : (String(sendErr.text || "").trim() || "WhatsApp could not send the list"));
        if (ok) {
            root.setStatus(message, false);
            root.clear();
        } else {
            root.setStatus(message, true);
        }
        root.sendFinished(ok, message);
        console.info("nbshell/shopping: send finished", code, ok ? "ok" : "failed");
    }

    Timer {
        id: saveTimer
        interval: 180
        onTriggered: store.setText(root.draft)
    }

    Process {
        id: sendProc
        property string pendingMessage: ""
        stdinEnabled: true
        stdout: StdioCollector { id: sendOut }
        stderr: StdioCollector { id: sendErr }
        // The draft goes over stdin, not argv: command-line arguments are
        // visible through process inspection for the whole lookup phase,
        // while stdin is only readable by this child process.
        onStarted: {
            write(pendingMessage);
            pendingMessage = "";
            stdinEnabled = false;
        }
        // Collectors finish in the same event-loop turn as Process::exited.
        // Defer parsing once so the final JSON is available before status and
        // draft state are committed.
        onExited: code => Qt.callLater(() => root.finishSend(code))
    }

    FileView {
        id: store
        path: root.file
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.draft = text();
            root.loaded = true;
            root.setStatus(root.draft.trim() === "" ? "Start with an item, a sentence, or a pasted list" : "Draft restored", false);
        }
        onLoadFailed: {
            root.loaded = true;
            root.setStatus("Start with an item, a sentence, or a pasted list", false);
        }
    }
}
