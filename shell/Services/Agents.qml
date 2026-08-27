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
    property var hermes: ({ "installed": false, "authenticated": false, "gateway": "inactive", "provider": "", "model": "", "selected": "codex", "mode": "restricted", "running": false, "sessions": [], "providers": ({}) })
    property var hermesJobs: []
    property var hermesTeams: []
    property var brainProposals: []
    property var brainProposalDetail: ({})
    property string selectedBrainProposalId: ""
    property var jobDetail: ({})
    property string selectedJobId: ""
    property var config: ({ "defaultAgent": "codex", "profile": "balanced", "modelProfile": "cloud" })
    property bool loading: false
    property string message: ""
    property bool sessionsReady: false
    property var attentionSessions: []
    property bool genericAttention: false
    property string attentionKind: ""

    readonly property bool completionAttention: genericAttention || attentionSessions.length > 0

    readonly property string defaultAgent: String(config.defaultAgent ?? "codex")
    readonly property string approvalProfile: String(config.profile ?? "balanced")
    readonly property string modelProfile: String(config.modelProfile ?? "cloud")
    readonly property string hermesProvider: String(config.hermesProvider ?? "codex")
    readonly property string hermesMode: String(config.hermesMode ?? "restricted")
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
    function setHermesProvider(id) { action(["hermes-provider", id]); }
    function setHermesMode(id) { action(["hermes-mode", id]); }
    function selectHermesJob(id) {
        selectedJobId = String(id || "");
        if (!selectedJobId || jobDetailProc.running) return;
        jobDetailProc.command = ["python3", root.tool, "hermes-job", "list", selectedJobId];
        jobDetailProc.running = true;
    }
    function hermesJobAction(name, id, provider) {
        var args = ["hermes-job", name, String(id)];
        if (provider) args = args.concat(["--provider", String(provider)]);
        if (["apply", "install", "push", "reject"].indexOf(name) >= 0) args.push("--yes");
        action(args);
    }
    function hermesTeamAction(name, id) {
        var args = ["hermes-team", name, String(id)];
        if (["apply", "install", "push", "reject"].indexOf(name) >= 0) args.push("--yes");
        action(args);
    }
    function selectBrainProposal(id) {
        selectedBrainProposalId = String(id || "");
        if (!selectedBrainProposalId || brainDetailProc.running) return;
        brainDetailProc.command = ["python3", root.tool, "hermes-brain", "list", selectedBrainProposalId];
        brainDetailProc.running = true;
    }
    function hermesBrainAction(name, id) {
        var args = ["hermes-brain", name, String(id)];
        if (["apply", "push", "reject"].includes(name)) args.push("--yes");
        action(args);
    }
    function launch(id, project) {
        var args = ["launch"];
        if (id) args.push(id);
        if (project) args = args.concat(["--project", project]);
        action(args);
    }
    function resumeHermes(id) {
        if (id) action(["launch", "hermes", "--resume", String(id)]);
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
    function requestAttention(kind, sessionId) {
        const rawId = String(sessionId ?? "");
        const id = rawId === "" ? "" : (rawId.indexOf("herdr:") === 0 ? rawId : "herdr:" + rawId);

        // Codex hooks run inside the Herdr pane and can report Stop while the
        // user is already looking at that exact task. Such an event is not
        // unread and must never start the animation in the first place.
        if (id !== "" && sessions.some(row => String(row.id) === id && Boolean(row.focused)))
            return;

        if (String(kind) === "decision" || !completionAttention)
            attentionKind = String(kind) === "decision" ? "decision" : "finished";
        if (id === "") {
            genericAttention = true;
        } else if (attentionSessions.indexOf(id) < 0) {
            attentionSessions = attentionSessions.concat([id]);
        }
    }
    function acknowledgeSession(id) {
        const target = String(id ?? "");
        if (target === "")
            return;
        attentionSessions = attentionSessions.filter(entry => entry !== target);
        if (!genericAttention && attentionSessions.length === 0)
            attentionKind = "";
    }
    function acknowledgeCompletions() {
        attentionSessions = [];
        genericAttention = false;
        attentionKind = "";
    }

    function sessionNotifications(next) {
        if (!sessionsReady) {
            sessionsReady = true;
            return;
        }
        const previous = {};
        for (const row of sessions)
            previous[String(row.id)] = row;

        // Visiting the actual Herdr pane acknowledges only that task. Opening
        // Agent Center alone is not enough: the user should have seen the
        // session that requested attention.
        const focused = next.filter(row => Boolean(row.focused)).map(row => String(row.id));
        if (focused.length > 0) {
            attentionSessions = attentionSessions.filter(id => focused.indexOf(id) < 0);
            if (genericAttention)
                genericAttention = false;
            if (!genericAttention && attentionSessions.length === 0)
                attentionKind = "";
        }

        for (const row of next) {
            const before = previous[String(row.id)];
            if (!before)
                continue;
            const wasWorking = String(before.status) === "working";
            const now = String(row.status);
            if (wasWorking && (now === "done" || now === "idle") && !row.focused)
                requestAttention("finished", row.id);
            if (row.focused || String(row.name).toLowerCase() === "codex")
                continue;
            const decision = now === "waiting" || now === "permission" || now === "blocked";
            if (decision && !["waiting", "permission", "blocked"].includes(String(before.status)))
                requestAttention("decision", row.id);
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
        // While the bar is asking for attention, notice a visit to the target
        // Herdr pane quickly. Return to the cheap background cadence once the
        // marker has been acknowledged.
        interval: root.completionAttention || Number(root.hermes.jobsRunning || 0) > 0 || Number(root.hermes.teamsRunning || 0) > 0 || Number(root.hermes.brainReviewing || 0) > 0 ? 2000 : 30000
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
                    root.hermes = data.hermes ?? ({ "installed": false, "authenticated": false, "gateway": "inactive", "provider": "", "model": "", "selected": "codex", "mode": "restricted", "running": false, "sessions": [], "providers": ({}) });
                    root.hermesJobs = root.hermes.jobs ?? [];
                    const previousAttention = root.hermesTeams.filter(row => ["awaiting_approval", "failed"].includes(String(row.status))).length;
                    root.hermesTeams = root.hermes.teams ?? [];
                    const previousBrainAttention = root.brainProposals.filter(row => ["awaiting_approval", "revision_requested", "failed"].includes(String(row.status))).length;
                    root.brainProposals = root.hermes.brainProposals ?? [];
                    const nextBrainAttention = root.brainProposals.filter(row => ["awaiting_approval", "revision_requested", "failed"].includes(String(row.status))).length;
                    if (nextBrainAttention > previousBrainAttention)
                        Quickshell.execDetached([root.notifyTool, "hermes-brain", "Second Brain proposal", "decision", "Review or approval required"]);
                    const nextAttention = root.hermesTeams.filter(row => ["awaiting_approval", "failed"].includes(String(row.status))).length;
                    if (nextAttention > previousAttention)
                        Quickshell.execDetached([root.notifyTool, "hermes-team", "Hermes team", "decision", "Review or approval required"]);
                    if (root.selectedJobId) root.selectHermesJob(root.selectedJobId);
                    if (root.selectedBrainProposalId) root.selectBrainProposal(root.selectedBrainProposalId);
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

    Process {
        id: brainDetailProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.brainProposalDetail = JSON.parse(text); }
                catch (e) { root.message = "Could not read Brain proposal"; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) root.message = String(text).trim().split("\n")[0] }
    }

    Process {
        id: jobDetailProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.jobDetail = JSON.parse(text); }
                catch (e) { root.message = "Could not read transaction details"; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) root.message = String(text).trim().split("\n")[0] }
    }


}
