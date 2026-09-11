import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// AI subscription dashboard inspired by Omarchy's information hierarchy,
// implemented with nbshell's own primitives and local-only usage aggregation.
Cell {
    id: root

    property int selectedProviderIndex: 0

    readonly property var monitorSessions: Agents.sessions.filter(row => row.backend === "herdr")
        .sort((a, b) => sessionRank(a) - sessionRank(b))
    readonly property var visibleSessions: monitorSessions.slice(0, 4)

    function sessionRank(row) {
        if (row.status === "working") return 0;
        if (["waiting", "permission", "blocked"].includes(row.status)) return 1;
        return 2;
    }

    function sessionState(row) {
        if (row.status === "working") return "Working";
        if (["waiting", "permission", "blocked"].includes(row.status)) return "Input";
        if (row.status === "done") return "Done";
        if (row.status === "idle") return "Idle";
        return "Unknown";
    }

    Component.onCompleted: Agents.monitorUsers++
    Component.onDestruction: Agents.monitorUsers = Math.max(0, Agents.monitorUsers - 1)
    onPreviewVisibleChanged: if (previewVisible) Agents.refreshSessions()

    readonly property bool agentActive: Agents.workingCount > 0 || Agents.waitingCount > 0
    readonly property bool limitWarning: AiUsage.list.some(entry =>
        (entry.limits ?? []).some(window => (window.percent ?? 0) >= 90))

    shown: monitorSessions.length > 0 || Agents.completionAttention || root.agentActive || (AiUsage.available && AiUsage.list.length > 0)
    interactive: true
    popoutTakesKeyboard: true
    slotChars: 5
    label: "AI"
    icon: Icons.agent
    text: Agents.workingCount > 0 ? "● " + Agents.workingCount
        : (Agents.waitingCount > 0 ? "! " + Agents.waitingCount : "")
    accessibilityName: "AI · " + Agents.workingCount + " working · " + Agents.waitingCount + " waiting"
    color: root.limitWarning ? Theme.red : (Agents.completionAttention ? (Agents.attentionKind === "decision" ? Theme.yellow : Theme.cyan) : (root.agentActive ? Theme.green : Theme.textDim))

    onPopoutVisibleChanged: Agents.setOverviewVisible(root.popoutVisible)

    SequentialAnimation on contentOpacity {
        running: Agents.completionAttention && !Theme.reducedMotion
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.contentOpacity = 1

        NumberAnimation { to: 0.28; duration: Theme.motionAttention; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Theme.motionAttention; easing.type: Easing.InOutSine }
    }

    onClicked: {
        if (Agents.completionAttention) {
            root.setPopout(false);
            const target = Agents.attentionSessions[0] ?? "";
            if (target !== "")
                Agents.focusSession(target);
            else
                Agents.refresh();
        }
    }
    onRightClicked: Agents.launch(Agents.defaultAgent, "")
    onMiddleClicked: {
        if (AiUsage.list.length > 0)
            root.selectedProviderIndex = (root.selectedProviderIndex + 1) % AiUsage.list.length;
    }
    onWheel: delta => {
        if (AiUsage.list.length > 0)
            root.selectedProviderIndex = (root.selectedProviderIndex + (delta < 0 ? 1 : -1) + AiUsage.list.length) % AiUsage.list.length;
    }

    preview: Component {
        BarPreview {
            id: card
            icon: Icons.agent
            title: "Herdr agents"
            subtitle: Agents.monitorError || (root.monitorSessions.length === 0
                ? "No active Herdr sessions"
                : Agents.workingCount + " working · " + Agents.waitingCount + " waiting")
            badge: Agents.monitorError ? "OFFLINE" : (Agents.workingCount > 0 ? "LIVE" : (Agents.waitingCount > 0 ? "INPUT" : "IDLE"))
            badgeColor: Agents.monitorError ? Theme.yellow : (Agents.workingCount > 0 ? Theme.green : (Agents.waitingCount > 0 ? Theme.yellow : Theme.fgDim))
            content: [
                Repeater {
                    model: root.visibleSessions
                    PanelRow {
                        required property var modelData
                        width: card.rowWidth
                        title: String(modelData.name || "Agent") + " · Tab " + String(modelData.tab || "—")
                        detail: String(modelData.title || modelData.project || "Herdr session")
                        value: root.sessionState(modelData)
                        glyph: modelData.status === "working" ? "●" : "·"
                    }
                },
                Line {
                    width: card.rowWidth
                    visible: root.monitorSessions.length > 4
                    text: "+" + (root.monitorSessions.length - 4) + " more sessions"
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                },
                Line {
                    width: card.rowWidth
                    text: Agents.completionAttention ? "Click to return to your agent"
                        : "Click for AI usage · Right-click to start an agent"
                    wrapMode: Text.WordWrap
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                }
            ]
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null
            property int selectedIndex: 0
            readonly property real rowWidth: 58 * Theme.cellW
            readonly property var provider: AiUsage.list.length > 0 ? AiUsage.list[selectedIndex] : null
            readonly property var stats: provider?.stats ?? ({ "recentDays": [], "models": [], "todayTokens": 0, "totalTokens": 0, "sessions": 0 })
            readonly property var limits: provider?.limits ?? []
            readonly property real dayPeak: Math.max(1, ...(stats.recentDays ?? []).map(day => Number(day.tokens ?? 0)))
            readonly property real modelPeak: Math.max(1, ...(stats.models ?? []).map(model => Number(model.tokens ?? 0)))

            spacing: Theme.cellH * 0.55
            focus: true

            onSelectedIndexChanged: root.selectedProviderIndex = selectedIndex
            Component.onCompleted: {
                selectedIndex = Math.min(root.selectedProviderIndex, Math.max(0, AiUsage.list.length - 1));
                forceActiveFocus();
            }

            Connections {
                target: root
                function onSelectedProviderIndexChanged() {
                    const next = Math.min(root.selectedProviderIndex, Math.max(0, AiUsage.list.length - 1));
                    if (panel.selectedIndex !== next)
                        panel.selectedIndex = next;
                }
            }

            Connections {
                target: AiUsage
                function onListChanged() {
                    const next = Math.min(panel.selectedIndex, Math.max(0, AiUsage.list.length - 1));
                    if (panel.selectedIndex !== next)
                        panel.selectedIndex = next;
                }
            }
            Keys.onLeftPressed: selectProvider(-1)
            Keys.onRightPressed: selectProvider(1)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_R || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    AiUsage.refresh();
                    event.accepted = true;
                }
            }

            function selectProvider(delta) {
                if (AiUsage.list.length === 0)
                    return;
                selectedIndex = (selectedIndex + delta + AiUsage.list.length) % AiUsage.list.length;
            }

            function dayLabel(value) {
                const date = new Date(String(value) + "T12:00:00");
                const today = new Date();
                if (date.toDateString() === today.toDateString())
                    return "Today";
                return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()];
            }

            component Meter: Item {
                id: meter
                property real value: 0
                property color fill: Theme.accent

                implicitHeight: Math.max(3, Theme.borderWidth * 2)

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.alpha(Theme.muted, 0.45)
                }

                Rectangle {
                    height: parent.height
                    width: Math.round(parent.width * Math.max(0, Math.min(1, meter.value)))
                    radius: height / 2
                    color: meter.fill
                }
            }

            component LimitRow: Column {
                id: limitRow
                required property var modelData

                width: panel.rowWidth
                spacing: Theme.cellH * 0.2

                Item {
                    width: parent.width
                    height: Theme.cellH

                    Line {
                        anchors.left: parent.left
                        anchors.right: limitValue.left
                        anchors.rightMargin: Theme.cellW
                        text: limitRow.modelData.label !== "" ? limitRow.modelData.label : "Session"
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    Line {
                        id: limitValue
                        anchors.right: parent.right
                        text: limitRow.modelData.percent + " %"
                        color: limitRow.modelData.percent >= 90 ? Theme.red : Theme.fgBright
                        font.bold: true
                    }
                }

                Meter {
                    width: parent.width
                    value: Number(limitRow.modelData.percent ?? 0) / 100
                    fill: limitRow.modelData.percent >= 90 ? Theme.red : Theme.accent
                }

                Line {
                    text: {
                        const reset = AiUsage.untilReset(limitRow.modelData);
                        return reset !== "" ? "Resets " + reset : "Reset time unavailable";
                    }
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                }
            }

            component UsageRow: Item {
                id: usageRow
                property string label: ""
                property real tokens: 0
                property real peak: 1
                property bool emphasized: false
                property real labelWidth: Theme.cellW * 8

                width: panel.rowWidth
                height: Theme.cellH * 1.35

                Line {
                    id: usageLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: usageRow.labelWidth
                    text: usageRow.label
                    color: usageRow.emphasized ? Theme.fgBright : Theme.fgDim
                    font.bold: usageRow.emphasized
                    elide: Text.ElideRight
                }

                Meter {
                    anchors.left: usageLabel.right
                    anchors.right: usageValue.left
                    anchors.rightMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    value: usageRow.tokens / Math.max(1, usageRow.peak)
                    fill: usageRow.emphasized ? Theme.accent : Theme.alpha(Theme.accent, 0.7)
                }

                Line {
                    id: usageValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.cellW * 8
                    horizontalAlignment: Text.AlignRight
                    text: AiUsage.formatTokens(usageRow.tokens)
                    color: usageRow.emphasized ? Theme.fgBright : Theme.fg
                    font.bold: usageRow.emphasized
                }
            }

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.agent
                title: panel.provider?.name ?? "AI subscriptions"
                subtitle: panel.provider?.plan ?? "No usage data"
                badge: panel.provider ? (panel.provider.percent + " %") : "—"
                badgeColor: panel.provider?.percent >= 90 ? Theme.red : Theme.accent
            }

            Row {
                visible: AiUsage.list.length > 1
                width: panel.rowWidth
                spacing: Theme.cellW

                Repeater {
                    model: AiUsage.list

                    ActionButton {
                        required property var modelData
                        required property int index
                        width: (panel.rowWidth - parent.spacing * (AiUsage.list.length - 1)) / AiUsage.list.length
                        text: modelData.id
                        tone: index === panel.selectedIndex ? "primary" : "secondary"
                        compact: true
                        onTriggered: panel.selectedIndex = index
                    }
                }
            }

            Rule {
                visible: panel.limits.length > 0
                rowWidth: panel.rowWidth
                label: "LIMITS"
            }

            Repeater {
                model: panel.limits
                LimitRow {}
            }

            Rule {
                visible: (panel.stats.recentDays ?? []).some(day => Number(day.tokens ?? 0) > 0)
                rowWidth: panel.rowWidth
                label: "TOKENS BY DAY"
            }

            Repeater {
                model: panel.stats.recentDays ?? []

                UsageRow {
                    required property var modelData
                    label: panel.dayLabel(modelData.date)
                    tokens: Number(modelData.tokens ?? 0)
                    peak: panel.dayPeak
                    emphasized: label === "Today"
                }
            }

            Rule {
                visible: (panel.stats.models ?? []).length > 0
                rowWidth: panel.rowWidth
                label: "TOKENS BY MODEL"
            }

            Repeater {
                model: panel.stats.models ?? []

                UsageRow {
                    required property var modelData
                    label: String(modelData.name ?? "model")
                    labelWidth: Theme.cellW * 20
                    tokens: Number(modelData.tokens ?? 0)
                    peak: panel.modelPeak
                }
            }

            Line {
                visible: panel.provider && (panel.stats.models ?? []).length === 0
                width: panel.rowWidth
                text: "No local token history for this provider"
                color: Theme.fgDim
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontCaption
            }

            Rule {
                rowWidth: panel.rowWidth
                label: "AGENTS"
            }

            Facts {
                rowWidth: panel.rowWidth
                pairs: [
                    { "label": "Running", "value": String(Agents.workingCount), "color": Agents.workingCount > 0 ? Theme.green : Theme.fgDim },
                    { "label": "Waiting", "value": String(Agents.waitingCount), "color": Agents.waitingCount > 0 ? Theme.yellow : Theme.fgDim },
                    { "label": "Local sessions", "value": String(panel.stats.sessions ?? 0), "color": Theme.fg }
                ]
            }

            Row {
                spacing: Theme.cellW

                ActionButton {
                    text: "Agent Center"
                    compact: true
                    onTriggered: {
                        panel.closePopout?.();
                        Runtime.agentCenterOpen = true;
                    }
                }

                ActionButton {
                    text: "Refresh"
                    compact: true
                    onTriggered: {
                        AiUsage.refresh();
                        Agents.refresh();
                    }
                }
            }

            Line {
                width: panel.rowWidth
                text: "←/→ provider · R refresh · right click launches default agent"
                color: Theme.muted
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontCaption
            }
        }
    }
}
