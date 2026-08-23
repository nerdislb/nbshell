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
    property var sessionBackend: ({ "native": false, "name": "herdr fallback", "migration": false })
    property bool loading: false
    property string message: ""
    property bool sessionsReady: false
    property string sessionOutput: ""
    property string selectedSession: ""
    property bool readingSession: false

    readonly property string defaultAgent: String(config.defaultAgent ?? "codex")
    readonly property string approvalProfile: String(config.profile ?? "balanced")
    readonly property string modelProfile: String(config.modelProfile ?? "cloud")
    readonly property int workingCount: sessions.filter(row => String(row.status) === "working").length
    readonly property int waitingCount: sessions.filter(row => ["waiting", "permission", "blocked"].indexOf(String(row.status)) >= 0).length

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
    function workspace(templateName, project) {
        var args = ["workspace", templateName, "--new-tab"];
        if (project) args = args.concat(["--project", project]);
        action(args);
    }
    function ollamaAction(name) { action(["ollama", name]); }
    function focusSession(id) {
        if (id) action(["session-focus", String(id)]);
    }
    function readSession(id) {
        if (!id || readProc.running)
            return;
        selectedSession = String(id);
        readingSession = true;
        readProc.command = ["python3", root.tool, "session-read", String(id)];
        readProc.running = true;
    }
    function promptSession(id, prompt) {
        if (id && String(prompt).trim() !== "")
            action(["session-prompt", String(id), String(prompt)]);
    }
    function quakeStart(id, project, prompt) {
        var args = ["quake-start", String(id)];
        if (project) args = args.concat(["--project", String(project)]);
        if (String(prompt).trim() !== "") args = args.concat(["--prompt", String(prompt)]);
        action(args);
    }
    function restoreSession(id) { if (id) action(["session-restore", String(id)]); }

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
            const decision = now === "waiting" || now === "permission" || now === "blocked";
            if ((wasWorking && now === "idle") || decision) {
                const label = String(row.name || "Agent");
                const project = String(row.project || row.title || "Agent session");
                Quickshell.execDetached([root.notifyTool, String(row.id), label, decision ? "decision" : "finished", project]);
            }
        }
    }

    Component.onCompleted: refresh()

    Timer {
        // Session changes are informative, not frame-critical. The status
        // helper inspects several agent backends, so a five-second idle poll
        // spent measurable CPU even while Agent Center was closed.
        interval: 30000
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
                    root.sessionBackend = data.sessionBackend ?? root.sessionBackend;
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

    Process {
        id: readProc
        stdout: StdioCollector { onStreamFinished: root.sessionOutput = String(text).trim() }
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) root.message = String(text).trim().split("\n")[0] }
        onExited: root.readingSession = false
    }
}
