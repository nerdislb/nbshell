pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root
    property var device: ({})
    Timer {
        interval: 60000
        running: root.desktopActive && root.moduleEnabled("device")
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!deviceProc.running) deviceProc.running = true
    }
    Process {
        id: deviceProc
        command: ["python3", "-c", "import json,shutil,socket; from pathlib import Path; d=shutil.disk_usage('/'); u=int(float(Path('/proc/uptime').read_text().split()[0])); print(json.dumps(dict(host=socket.gethostname(),disk=f'DISK /  {d.free/2**30:.1f} GiB free / {d.total/2**30:.1f} GiB',uptime=f'{u//86400}d {u//3600%24}h {u//60%60}m')))" ]
        stdout: StdioCollector { onStreamFinished: { try { root.device = JSON.parse(text); } catch (e) { root.device = ({}); } } }
        onExited: (code, status) => { if (code !== 0) root.device = ({}); }
    }
    property bool dashboardActive: false
    readonly property bool desktopActive: Config.value("workDesktop", false)
    function moduleEnabled(name) { return Config.value("workModule_" + name, true); }
    readonly property bool active: dashboardActive || (desktopActive && (moduleEnabled("sessions") || moduleEnabled("git")))
    readonly property bool gitActive: dashboardActive || (desktopActive && moduleEnabled("git"))
    function openSession(row) {
        if (row.backend === "openclaw") Qt.openUrlExternally(row.url);
        else Agents.focusSession(row.id);
    }
    property var projects: ({})
    property string projectError: ""
    readonly property var rows: Agents.sessions.concat(Agents.openclaw.online ? (Agents.openclaw.items || []) : []).slice().sort((a, b) => rank(a) - rank(b) || Number(b.updatedAt || 0) - Number(a.updatedAt || 0))
    readonly property var paths: [...new Set(rows.map(row => String(row.project || "")).concat(Config.value("workProjects", [])).filter(p => p.startsWith("/")))].sort().slice(0, 12)
    function rank(row) {
        return ["waiting", "permission", "blocked"].includes(row.status) ? 0 : row.status === "working" ? 1 : 2;
    }
    function statusText(row) {
        return ({working: "Working", idle: "Idle", waiting: "Needs input", permission: "Needs permission", blocked: "Blocked", done: "Done"})[row.status] || "Unknown";
    }
    function projectText(row) {
        if (!row.project) return "Project not provided";
        const git = projects[row.project];
        if (!git) return row.project + " · " + (paths.includes(row.project) ? "checking Git…" : "Git limit reached");
        if (git.error) return row.project + " · " + git.error;
        return git.root + " · " + git.branch + " · " + (git.conflicts ? git.conflicts + " conflicts · " : "") + git.changed + " changes";
    }
    function refreshGit() {
        if (!gitActive || gitProc.running) return;
        gitProc.command = ["python3", Qt.resolvedUrl("../scripts/work-projects.py").toString().replace("file://", ""), JSON.stringify(paths)];
        gitProc.running = true;
    }
    onActiveChanged: if (active) { Agents.refreshSessions(); refreshGit(); }
    onPathsChanged: refreshGit()
    Timer { interval: 15000; repeat: true; running: root.gitActive; triggeredOnStart: true; onTriggered: root.refreshGit() }
    Process {
        id: gitProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.projects = JSON.parse(text); root.projectError = ""; }
                catch (e) { root.projects = ({}); root.projectError = "Project status unavailable"; }
            }
        }
        onExited: (code, status) => { if (code !== 0) { root.projects = ({}); root.projectError = "Project status unavailable"; } }
    }
}
