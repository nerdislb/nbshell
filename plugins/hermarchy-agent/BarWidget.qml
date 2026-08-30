import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// A deliberately narrow comparison surface. It reuses the resident Agents
// service and adds no process, timer, database reader, or second agent backend.
Cell {
    id: root

    readonly property var session: (Agents.hermes.sessions || []).find(row => Boolean(row.active))
        || ((Agents.hermes.sessions || [])[0] ?? ({}))
    readonly property var jobs: Agents.hermes.jobs || []
    readonly property var teams: Agents.hermes.teams || []
    readonly property var proposals: Agents.hermes.brainProposals || []
    readonly property int activeWorkers: Number(Agents.hermes.jobsRunning || 0)
        + Number(Agents.hermes.teamsRunning || 0)
        + Number(Agents.hermes.brainReviewing || 0)
    readonly property bool needsInput: Agents.waitingCount > 0
        || (Agents.completionAttention && Agents.attentionKind === "decision")
        || teams.some(row => ["awaiting_approval", "revision_requested"].includes(String(row.status)))
        || proposals.some(row => ["awaiting_approval", "revision_requested"].includes(String(row.status)))
    readonly property bool executing: Boolean(session.active) || Agents.workingCount > 0 || activeWorkers > 0
    readonly property bool failed: jobs.some(row => String(row.status) === "failed")
        || teams.some(row => String(row.status) === "failed")
        || proposals.some(row => String(row.status) === "failed")
    readonly property bool completed: Agents.completionAttention && Agents.attentionKind !== "decision"
    readonly property string agentState: {
        if (!Agents.hermes.installed) return "unavailable";
        if (executing) return "executing";
        if (needsInput) return "waiting";
        if (failed) return "failed";
        if (completed) return "completed";
        return Agents.hermes.running ? "idle" : "offline";
    }
    readonly property string suffix: {
        if (agentState === "executing") return "● RUN";
        if (agentState === "waiting") return "● INPUT";
        if (agentState === "completed") return "● DONE";
        if (agentState === "failed") return "● FAIL";
        return "·";
    }
    readonly property color stateColor: {
        if (agentState === "executing") return Theme.cyan;
        if (agentState === "waiting") return Theme.yellow;
        if (agentState === "completed") return Theme.green;
        if (agentState === "failed") return Theme.red;
        return Theme.fgDim;
    }
    readonly property int tokenCount: Number(session.inputTokens || 0) + Number(session.outputTokens || 0)

    function compact(value) {
        const count = Number(value || 0);
        if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1) + "M";
        if (count >= 1000) return (count / 1000).toFixed(count >= 10000 ? 0 : 1) + "K";
        return String(count);
    }

    shown: Agents.hermes.installed || Agents.hermes.running
    interactive: true
    popoutTakesKeyboard: true
    slotChars: agentState === "idle" || agentState === "offline" ? 7 : 13
    label: "HERMES"
    icon: ""
    text: suffix
    color: stateColor

    onClicked: Agents.refresh()
    onRightClicked: Runtime.agentCenterOpen = true

    preview: Component {
        BarPreview {
            icon: Icons.agent
            title: "Hermarchy signal"
            subtitle: String(root.session.title || "No active Hermes task")
            badge: root.agentState.toUpperCase()
            badgeColor: root.stateColor
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Model", "value": String(root.session.model || Agents.hermes.model || "—") },
                        { "label": "Workers", "value": String(root.activeWorkers), "color": root.executing ? Theme.cyan : Theme.fgDim },
                        { "label": "Tokens", "value": root.compact(root.tokenCount) },
                        { "label": "Gateway", "value": String(Agents.hermes.gateway || "unknown") }
                    ]
                }
            ]
        }
    }

    popout: Component {
        Column {
            id: panel
            property var closePopout: null
            readonly property real rowWidth: 48 * Theme.cellW
            spacing: Theme.cellH * 0.55
            focus: true

            Component.onCompleted: forceActiveFocus()
            Keys.onEscapePressed: if (closePopout) closePopout()

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.agent
                title: "Hermes state"
                subtitle: String(root.session.title || "Compact comparison view")
                badge: root.agentState.toUpperCase()
                badgeColor: root.stateColor
            }

            Rule {
                rowWidth: panel.rowWidth
                label: "OBSERVED BY NBSHELL"
            }

            Facts {
                rowWidth: panel.rowWidth
                pairs: [
                    { "label": "Model", "value": String(root.session.model || Agents.hermes.model || "—") },
                    { "label": "Provider", "value": String(root.session.provider || Agents.hermes.provider || "—") },
                    { "label": "Workers", "value": String(root.activeWorkers), "color": root.executing ? Theme.cyan : Theme.fgDim },
                    { "label": "Tokens", "value": root.compact(root.tokenCount) },
                    { "label": "Gateway", "value": String(Agents.hermes.gateway || "unknown") }
                ]
            }

            Line {
                width: panel.rowWidth
                text: "This compact signal reuses nbshell's existing Hermes data and adds no poller."
                color: Theme.fgDim
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }

            ActionButton {
                width: panel.rowWidth
                text: "Open full Agent Center"
                tone: "secondary"
                onTriggered: {
                    if (panel.closePopout) panel.closePopout();
                    Runtime.agentCenterOpen = true;
                }
            }
        }
    }
}
