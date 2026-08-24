import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Compact AI status. Detailed limits and sessions belong in the popout; the
// bar only communicates whether an agent is active or a limit needs attention.
Cell {
    id: root

    readonly property bool agentActive: Agents.workingCount > 0 || Agents.waitingCount > 0
    readonly property bool limitWarning: AiUsage.list.some(entry =>
        (entry.percent ?? 0) >= 90 || (entry.more ?? []).some(window => (window.percent ?? 0) >= 90))

    shown: Agents.completionAttention || root.agentActive || (AiUsage.available && AiUsage.list.length > 0)
    interactive: true
    slotChars: 1
    label: "AI"
    icon: Icons.agent
    text: ""
    color: root.limitWarning ? Theme.red : (Agents.completionAttention ? (Agents.attentionKind === "decision" ? Theme.yellow : Theme.cyan) : (root.agentActive ? Theme.green : Theme.textDim))

    SequentialAnimation on contentOpacity {
        running: Agents.completionAttention
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.contentOpacity = 1

        NumberAnimation { to: 0.28; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }

    onClicked: {
        if (Agents.completionAttention) {
            const target = Agents.attentionSessions[0] ?? "";
            if (target !== "")
                Agents.focusSession(target);
            else
                Agents.refresh();
        } else
            AiUsage.refresh();
    }
    onRightClicked: Runtime.agentCenterOpen = true

    preview: Component {
        BarPreview {
            id: card
            readonly property var highest: AiUsage.list.reduce((best, entry) =>
                !best || (entry.percent ?? 0) > (best.percent ?? 0) ? entry : best, null)

            icon: Icons.agent
            title: "AI agents"
            subtitle: Agents.completionAttention ? (Agents.attentionKind === "decision" ? "Agent needs your input" : "Agent task completed") : (root.agentActive ? "Work in progress" : "No active session")
            badge: Agents.completionAttention ? (Agents.attentionKind === "decision" ? "INPUT" : "NEW") : (root.agentActive ? "ACTIVE" : "IDLE")
            badgeColor: root.limitWarning ? Theme.red : (Agents.completionAttention ? (Agents.attentionKind === "decision" ? Theme.yellow : Theme.cyan) : (root.agentActive ? Theme.green : Theme.fgDim))
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Running", "value": String(Agents.workingCount), "color": Agents.workingCount > 0 ? Theme.green : Theme.fgDim },
                        { "label": "Waiting", "value": String(Agents.waitingCount), "color": Agents.waitingCount > 0 ? Theme.yellow : Theme.fgDim },
                        { "label": "Highest limit", "value": card.highest ? (card.highest.id + "  " + card.highest.percent + " %") : "unavailable", "color": root.limitWarning ? Theme.red : Theme.fg }
                    ]
                }
            ]
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            // 46 statt 34 Zeichen: seit Antigravity dazukam, stehen dort
            // Modellgruppen ("Claude & OpenAI Models") statt kurzer Fenster
            // ("5 hour") -- bei 34 brach schon die erste Zeile ab.
            readonly property real rowWidth: 46 * Theme.cellW

            spacing: Theme.cellH * 0.3

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.agent
                title: "AI usage"
                subtitle: "Model limits and active agents"
                badge: String(AiUsage.list.length)
            }

            Repeater {
                model: AiUsage.list

                Column {
                    id: entry

                    required property var modelData

                    width: panel.rowWidth
                    spacing: 0

                    Line {
                        width: panel.rowWidth
                        elide: Text.ElideRight
                        text: {
                            const time = AiUsage.untilReset(entry.modelData);
                            var s = entry.modelData.id + "   " + entry.modelData.percent + "%";
                            if (entry.modelData.window !== "")
                                s += "   " + entry.modelData.window;
                            if (time !== "")
                                s += (entry.modelData.window !== "" ? ", " : "   ") + time;
                            return s;
                        }
                        color: entry.modelData.percent >= 90 ? Theme.red : Theme.fg
                    }

                    LevelBar {
                        cells: 30
                        value: entry.modelData.percent
                        interactive: false
                        fillColor: entry.modelData.percent >= 90 ? Theme.red : Theme.accent
                    }

                    // Die weiteren Toepfe desselben Anbieters. Codex und Claude
                    // koennen weitere Zeitfenster haben, Antigravity Modellgruppen.
                    Repeater {
                        model: entry.modelData.more ?? []

                        Line {
                            required property var modelData

                            width: panel.rowWidth
                            elide: Text.ElideRight
                            text: {
                                const time = AiUsage.untilReset(modelData);
                                var s = "        " + modelData.percent + "%";
                                if (modelData.label !== "")
                                    s += "   " + modelData.label;
                                if (time !== "")
                                    s += (modelData.label !== "" ? ", " : "   ") + time;
                                return s;
                            }
                            color: modelData.percent >= 90 ? Theme.red : Theme.fgDim
                        }
                    }
                }
            }

            Line {
                text: Agents.completionAttention ? "Click opens the task" : "Click refreshes · right click opens Agent Center"
                color: Theme.muted
            }
        }
    }
}
