import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root
    property bool active: false
    property var projects: ({})
    property string projectError: ""
    signal openSession(var row)
    readonly property var rows: Agents.sessions.concat(Agents.openclaw.online ? (Agents.openclaw.items || []) : []).slice().sort((a, b) => rank(a) - rank(b) || Number(b.updatedAt || 0) - Number(a.updatedAt || 0))
    readonly property var paths: [...new Set(rows.map(row => String(row.project || "")).filter(p => p.startsWith("/")))].sort().slice(0, 12)
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
        if (!active || gitProc.running) return;
        gitProc.command = ["python3", Qt.resolvedUrl("../scripts/work-projects.py").toString().replace("file://", ""), JSON.stringify(paths)];
        gitProc.running = true;
    }
    onActiveChanged: {
        Agents.workVisible = active;
        if (active) { Agents.refreshSessions(); refreshGit(); }
    }
    onPathsChanged: refreshGit()
    Component.onDestruction: Agents.workVisible = false
    Timer { interval: 15000; repeat: true; running: root.active; onTriggered: root.refreshGit() }
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
    Column {
        anchors.fill: parent
        anchors.margins: Theme.spaceSm
        spacing: Theme.spaceSm
        Line {
            width: parent.width
            text: "WORK  ·  " + root.rows.filter(r => root.rank(r) === 0).length + " need you  ·  " + root.rows.filter(r => r.status === "working").length + " working"
            color: Theme.fgBright
            elide: Text.ElideRight
        }
        Line {
            width: parent.width
            text: [Agents.monitorError, Agents.openclaw.error, root.projectError].filter(Boolean).join(" · ") || "Herdr + OpenClaw · Select a session to open it · Git refreshes every 15s"
            color: Agents.monitorError || Agents.openclaw.error || root.projectError ? Theme.yellow : Theme.fgDim
            elide: Text.ElideRight
        }
        Flickable {
            id: scroll
            width: parent.width
            height: parent.height - y
            clip: true
            contentWidth: width
            contentHeight: entries.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: entries
                width: scroll.width
                spacing: Theme.spaceXs
                Line { visible: !root.rows.length; text: "No sessions available"; color: Theme.fgDim }
                Repeater {
                    model: root.rows
                    InteractiveSurface {
                        id: entry
                        required property var modelData
                        width: entries.width
                        height: content.height + Theme.spaceSm * 2
                        accessibleName: modelData.title || modelData.name || "Session"
                        accessibleDescription: root.statusText(modelData) + " · " + root.projectText(modelData)
                        onTriggered: root.openSession(modelData)
                        onActiveFocusChanged: if (activeFocus) scroll.contentY = Math.max(0, Math.min(y, Math.max(scroll.contentY, y + height - scroll.height)))
                        color: Theme.controlFill(hovered || visualFocus, false, false)
                        border.width: Theme.borderWidth
                        border.color: visualFocus ? Theme.focusBorder : Theme.panelBorder
                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        readonly property bool hovered: hover.hovered
                        TapHandler { onTapped: entry.activate() }
                        Column {
                            id: content
                            x: Theme.spaceSm
                            y: Theme.spaceSm
                            width: parent.width - Theme.spaceSm * 2
                            spacing: Theme.spaceXs
                            Line {
                                width: parent.width
                                text: (entry.modelData.backend === "openclaw" ? "OPENCLAW" : "HERDR") + " · " + root.statusText(entry.modelData) + " · " + (entry.modelData.title || entry.modelData.name || "Session")
                                color: root.rank(entry.modelData) === 0 ? Theme.yellow : entry.modelData.status === "working" ? Theme.green : Theme.fg
                                elide: Text.ElideRight
                            }
                            Line {
                                width: parent.width
                                text: entry.modelData.progress || (entry.modelData.backend === "openclaw" ? entry.modelData.id : entry.modelData.name || "")
                                color: Theme.fgDim
                                elide: Text.ElideRight
                            }
                            Line {
                                width: parent.width
                                text: root.projectText(entry.modelData)
                                color: (root.projects[entry.modelData.project] || {}).conflicts ? Theme.red : Theme.fgDim
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
                Line {
                    visible: Number(Agents.openclaw.detailTotal || 0) > (Agents.openclaw.items || []).length
                    text: "Showing the 40 most recent OpenClaw sessions"
                    color: Theme.fgDim
                }
            }
        }
    }
}
