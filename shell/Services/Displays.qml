pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string tool: Qt.resolvedUrl("../scripts/displays.py").toString().replace("file://", "")
    property var outputs: []
    property bool loading: false
    property string error: ""
    property string selectedName: ""
    readonly property var selected: outputs.find(row => row.name === selectedName) ?? (outputs[0] ?? null)

    function refresh() {
        if (statusProc.running) return;
        loading = true;
        statusProc.running = true;
    }

    function action(args) {
        if (actionProc.running) return;
        error = "";
        actionProc.command = ["python3", tool].concat(args);
        actionProc.running = true;
    }

    function setValue(name, key, value) { action(["set", name, key, String(value)]); }
    function place(name, relation, reference) { action(["place", name, relation, reference]); }

    Component.onCompleted: refresh()

    // DisplayPanel refreshes immediately when opened and after every action.
    // This slow fallback only catches an external hot-plug while it is closed.
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.refresh() }

    Process {
        id: statusProc
        command: ["python3", root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.outputs = data.outputs ?? [];
                    if (!root.selectedName || !root.outputs.some(row => row.name === root.selectedName)) {
                        const focused = root.outputs.find(row => row.focused);
                        root.selectedName = focused?.name ?? (root.outputs[0]?.name ?? "");
                    }
                    root.error = "";
                } catch (e) {
                    root.error = "Could not read Umbriel outputs";
                }
                root.loading = false;
            }
        }
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) root.error = String(text).trim().split("\n")[0] }
        onExited: root.loading = false
    }

    Process {
        id: actionProc
        stdout: StdioCollector {}
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) root.error = String(text).trim().split("\n")[0] }
        onExited: function(code) {
            if (code === 0) root.error = "";
            refreshDelay.restart();
        }
    }

    Timer { id: refreshDelay; interval: 250; onTriggered: root.refresh() }
}
