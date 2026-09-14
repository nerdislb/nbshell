pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string script: Qt.resolvedUrl("../scripts/upstream-audit.py").toString().replace("file://", "")
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/nbshell/fork-updates"
    property var sources: []
    property string checkedAt: ""
    property string error: ""
    property bool busy: false
    property bool checking: false
    property bool reloadPending: false
    property bool watchReady: false
    readonly property int errorCount: sources.filter(r => r.status === "error").length
    readonly property int attentionCount: sources.filter(r => (r.status === "review" || r.status === "diverged")
        && r.decision === "pending" && r.scope !== "reference").length
    readonly property int approvedCount: sources.filter(r => r.decision === "approved").length

    function run(args, refresh) {
        if (root.busy)
            return;
        root.busy = true;
        root.checking = refresh;
        if (args[0] !== "--cached") root.error = "";
        process.command = ["python3", root.script, "--json"].concat(args);
        process.running = true;
    }
    function load() {
        if (root.busy) {
            root.reloadPending = true;
            return;
        }
        root.run(["--cached"], false);
    }
    function refresh() { root.run([], true); }
    function decide(row, decision) {
        if (!row.token || root.busy)
            return;
        root.run(["--decision", decision, "--source", row.id, "--token", row.token], false);
    }
    function openChanges(row) {
        const url = row.comparisonUrl || row.repository;
        if (/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]+$/.test(url))
            Quickshell.execDetached(["xdg-open", url]);
    }
    Component.onCompleted: root.load()
    FileView {
        path: root.watchReady ? root.stateDir + "/snapshot.json" : ""
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); root.load(); }
    }
    FileView {
        path: root.watchReady ? root.stateDir + "/decisions.json" : ""
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); root.load(); }
    }
    Process {
        id: process
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (!Array.isArray(data.sources)) {
                        root.error = data.error || qsTr("Unreadable fork check result");
                    } else {
                        root.sources = data.sources;
                        root.watchReady = true;
                        root.checkedAt = data.checkedAt || "";
                    }
                } catch (e) {
                    root.error = qsTr("Unreadable fork check result");
                }
            }
        }
        onRunningChanged: {
            if (!running) Qt.callLater(() => {
                // FailedToStart may not emit exited. Normal exits clear busy first.
                if (root.busy && !process.running) {
                    root.error = qsTr("Fork helper could not start; try Refresh again");
                    root.busy = false;
                    root.checking = false;
                    root.reloadPending = false;
                }
            });
        }
        onExited: code => {
            if (code !== 0 && root.error === "" && !root.sources.some(r => r.status === "error"))
                root.error = qsTr("Fork check failed; saved results may be stale");
            root.busy = false;
            root.checking = false;
            if (root.reloadPending) {
                root.reloadPending = false;
                Qt.callLater(root.load);
            }
        }
    }
}
