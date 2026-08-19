pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string tool: Qt.resolvedUrl("../scripts/agents.py").toString().replace("file://", "")
    readonly property string notifyTool: Qt.resolvedUrl("../scripts/agent-notify.sh").toString().replace("file://", "")
    property var agents: []
    property var projects: []
    property var sessions: []
    property var ollama: ({ "installed": false, "running": false, "models": [] })
    property var config: ({ "defaultAgent": "codex", "profile": "balanced", "modelProfile": "cloud" })
    property bool loading: false
    property string message: ""
    property bool sessionsReady: false

    readonly property string defaultAgent: String(config.defaultAgent ?? "codex")
    readonly property string approvalProfile: String(config.profile ?? "balanced")
    readonly property string modelProfile: String(config.modelProfile ?? "cloud")

    function refresh() {
        if (status.running)
            return;
        loading = true;
        status.running = true;
    }

    function action(args) {
        if (actionProc.running)
            return;
        actionProc.command = ["python3", root.tool].concat(args);
        actionProc.running = true;
    }

    function setDefault(id) { action(["default", id]); }
    function setProfile(id) { action(["profile", id]); }
    function setModelProfile(id) { action(["model-profile", id]); }
    function launch(id, project) {
        var args = ["launch"];
        if (id) args.push(id);
        if (project) args = args.concat(["--project", project]);
        action(args);
    }
    function install(id) { action(["install", id]); }
    function ollamaAction(name) { action(["ollama", name]); }
    function focusSession(id) {
        if (id) Quickshell.execDetached(["herdr", "agent", "focus", id]);
    }

    function sessionNotifications(next) {
        if (!sessionsReady) {
            sessionsReady = true;
            return;
        }
        const previous = {};
        for (const row of sessions)
            previous[String(row.id)] = row;
        for (const row of next) {
            const before = previous[String(row.id)];
            if (!before || row.focused || String(row.name).toLowerCase() === "codex")
                continue;
            const wasWorking = String(before.status) === "working";
            const now = String(row.status);
            const decision = now === "waiting" || now === "permission";
            if ((wasWorking && now === "idle") || decision) {
                const label = String(row.name || "Agent");
                const project = String(row.project || row.title || "Agent session");
                Quickshell.execDetached([root.notifyTool, String(row.id), label, decision ? "decision" : "finished", project]);
            }
        }
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: clearMessage
        interval: 5000
        onTriggered: root.message = ""
    }

    Process {
        id: status
        command: ["python3", root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const data = JSON.parse(text);
                    root.agents = data.agents ?? [];
                    root.projects = data.projects ?? [];
                    const nextSessions = data.sessions ?? [];
                    root.sessionNotifications(nextSessions);
                    root.sessions = nextSessions;
                    root.ollama = data.ollama ?? ({ "installed": false, "running": false, "models": [] });
                    root.config = data.config ?? root.config;
                } catch (e) {
                    root.message = "Could not read agent status";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (String(text).trim()) root.message = String(text).trim().split("\n")[0]
        }
        onExited: root.loading = false
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                const output = String(text).trim();
                if (output && output[0] !== "{") root.message = output.split("\n")[0];
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const output = String(text).trim();
                if (output) root.message = output.split("\n")[0];
            }
        }
        onExited: {
            clearMessage.restart();
            root.refresh();
        }
    }
}
