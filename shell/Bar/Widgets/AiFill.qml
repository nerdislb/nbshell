import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Quiet bar indicator; quota details belong in the hover and dashboard.
Cell {
    id: root

    readonly property bool agentActive: Agents.workingCount > 0
    readonly property bool limitWarning: AiUsage.list.some(provider =>
        (provider.limits ?? []).some(limit => Number(limit.percent ?? 0) >= 90))
    readonly property real panelWidth: Math.max(20 * Theme.cellW, Math.min(58 * Theme.cellW,
        (Quickshell.screens.find(screen => screen.name === root.popupOutput)?.width ?? 800) - Theme.panelPadding * 4))
    property double resetTick: Date.now()

    function percent(value) {
        return value === null || value === undefined || !isFinite(Number(value)) ? "—" : Math.round(Number(value)) + "%";
    }

    function asciiMeter(value, length) {
        if (value === null || value === undefined || !isFinite(Number(value)))
            return "[" + "·".repeat(length) + "]";
        const filled = Math.round(Math.max(0, Math.min(100, Number(value))) * length / 100);
        return "[" + "█".repeat(filled) + "░".repeat(length - filled) + "]";
    }

    function resetText(limit) {
        const tick = root.resetTick; // Minute cadence without refetching provider data.
        const text = AiUsage.untilReset(limit);
        return text ? (/^Resets /i.test(text) ? text : "Resets " + text) : "Reset unavailable";
    }

    function headline(provider) {
        const limits = provider.limits ?? [];
        return limits.length ? limits.reduce((a, b) => Number(a.percent ?? 0) >= Number(b.percent ?? 0) ? a : b) : null;
    }

    Component.onCompleted: Agents.monitorUsers++
    Component.onDestruction: Agents.monitorUsers = Math.max(0, Agents.monitorUsers - 1)
    onPreviewVisibleChanged: if (previewVisible) root.resetTick = Date.now()
    onPopoutVisibleChanged: if (popoutVisible) root.resetTick = Date.now()
    Timer {
        interval: 60000
        running: root.previewVisible || root.popoutVisible
        repeat: true
        onTriggered: root.resetTick = Date.now()
    }

    shown: Agents.sessions.length > 0 || Agents.openclaw.installed || root.agentActive || AiUsage.available
    interactive: true
    popoutTakesKeyboard: true
    slotChars: 0
    label: "AI"
    icon: Icons.agent
    text: ""
    color: root.limitWarning ? Theme.red : (root.agentActive ? Theme.green : Theme.textDim)
    accessibilityName: "AI limits · " + (root.limitWarning ? "Limit warning" : root.agentActive ? "Agent active" : "Idle")
    // Click always opens quotas, even when an agent has finished.
    onRightClicked: Agents.launch(Agents.defaultAgent, "")
    onMiddleClicked: AiUsage.refresh()

    preview: Component {
        BarPreview {
            id: card
            icon: Icons.agent
            title: "AI limits"
            subtitle: "Subscriptions & quotas"
            badge: root.limitWarning ? "LIMIT" : ""
            badgeColor: Theme.red
            content: [
                Repeater {
                    model: AiUsage.list
                    Column {
                        required property var modelData
                        width: card.rowWidth
                        spacing: Theme.spaceXs
                        Line {
                            width: parent.width
                            text: modelData.name
                            color: Theme.fgBright
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: modelData.limits ?? []
                            Column {
                                required property var modelData
                                width: card.rowWidth
                                spacing: 0
                                Line {
                                    width: parent.width
                                    text: (modelData.label || "Session") + " · " + root.percent(modelData.percent)
                                    color: modelData.percent >= 90 ? Theme.readable(Theme.red, Theme.bg, 4.5) : Theme.fg
                                    elide: Text.ElideRight
                                }
                                Line {
                                    width: parent.width
                                    text: root.asciiMeter(modelData.percent, 10) + " " + root.resetText(modelData)
                                    color: Theme.fgDim
                                    font.pixelSize: Theme.fontCaption
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        Line {
                            visible: !(modelData.limits ?? []).length
                            text: "Limits unavailable"
                            color: Theme.fgDim
                            font.pixelSize: Theme.fontCaption
                        }
                    }
                },
                Line {
                    visible: !AiUsage.list.length
                    text: AiUsage.discovering ? "Loading limits…" : "No usage data available"
                    color: Theme.fgDim
                },
                Line {
                    text: "Click for all providers"
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
            property alias initialFocusItem: limitsTab
            property string tab: "limits"
            property var expanded: ({})
            readonly property real rowWidth: root.panelWidth
            width: rowWidth
            spacing: Theme.spaceMd

            function toggleProvider(id) {
                const next = Object.assign({}, expanded);
                next[id] = !(expanded[id] ?? true);
                expanded = next;
            }
            function expandAll() {
                const allOpen = AiUsage.list.every(provider => expanded[provider.id] ?? true);
                const next = {};
                for (const provider of AiUsage.list) next[provider.id] = !allOpen;
                expanded = next;
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_R) { AiUsage.refresh(); event.accepted = true; }
                if (event.key === Qt.Key_E) { panel.expandAll(); event.accepted = true; }
                if (event.key === Qt.Key_Escape) { panel.closePopout?.(); event.accepted = true; }
            }

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.agent
                title: "AI Limits & Quotas"
                subtitle: "All subscriptions in one place"
                badge: root.limitWarning ? "LIMIT" : ""
                badgeColor: Theme.red
            }
            Row {
                spacing: Theme.spaceSm
                ActionButton {
                    id: limitsTab
                    width: (panel.rowWidth - parent.spacing) / 2
                    text: "Limits"
                    tone: panel.tab === "limits" ? "primary" : "secondary"
                    onTriggered: panel.tab = "limits"
                }
                ActionButton {
                    width: (panel.rowWidth - parent.spacing) / 2
                    text: "Token usage"
                    tone: panel.tab === "tokens" ? "primary" : "secondary"
                    onTriggered: panel.tab = "tokens"
                }
            }
            Flow {
                width: panel.rowWidth
                spacing: Theme.spaceSm
                ActionButton { text: "Refresh"; compact: true; onTriggered: AiUsage.refresh() }
                ActionButton {
                    text: AiUsage.list.every(provider => panel.expanded[provider.id] ?? true) ? "Collapse all" : "Expand all"
                    compact: true
                    enabled: AiUsage.list.length > 0
                    onTriggered: panel.expandAll()
                }
            }

            Repeater {
                model: AiUsage.list
                PanelSurface {
                    id: providerCard
                    required property var modelData
                    readonly property bool expanded: panel.expanded[modelData.id] ?? true
                    readonly property var headline: root.headline(modelData)
                    width: panel.rowWidth
                    height: providerBody.implicitHeight + Theme.spaceSm * 2
                    Column {
                        id: providerBody
                        x: Theme.spaceSm
                        y: Theme.spaceSm
                        width: parent.width - Theme.spaceSm * 2
                        spacing: Theme.spaceSm
                        PanelRow {
                            width: parent.width
                            title: providerCard.modelData.name
                            detail: providerCard.modelData.plan || "Subscription"
                            value: root.percent(providerCard.headline?.percent)
                            glyph: providerCard.expanded ? "▾" : "▸"
                            interactive: true
                            accessibleDescription: (providerCard.expanded ? "Collapse" : "Expand") + " provider limits"
                            onTriggered: panel.toggleProvider(providerCard.modelData.id)
                        }
                        Column {
                            width: parent.width
                            spacing: Theme.spaceSm
                            visible: providerCard.expanded
                            Repeater {
                                model: panel.tab === "limits" ? (providerCard.modelData.limits ?? []) : []
                                PanelSurface {
                                    id: quotaCard
                                    required property var modelData
                                    width: parent.width
                                    height: quotaBody.implicitHeight + Theme.spaceMd * 2
                                    raised: true
                                    Column {
                                        id: quotaBody
                                        x: Theme.spaceMd
                                        y: Theme.spaceMd
                                        width: parent.width - Theme.spaceMd * 2
                                        spacing: Theme.spaceXs
                                        Item {
                                            width: parent.width
                                            height: Theme.cellH
                                            Line {
                                                width: parent.width - quotaPercent.implicitWidth - Theme.spaceSm
                                                text: quotaCard.modelData.label || "Session"
                                                color: Theme.fgBright
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Line {
                                                id: quotaPercent
                                                anchors.right: parent.right
                                                text: root.percent(quotaCard.modelData.percent)
                                                color: quotaCard.modelData.percent >= 90 ? Theme.readable(Theme.red, Theme.panelSurfaceRaised, 4.5) : Theme.fgBright
                                                font.bold: true
                                            }
                                        }
                                        Line {
                                            width: parent.width
                                            text: root.asciiMeter(quotaCard.modelData.percent, Math.max(8, Math.min(24, Math.floor(width / Theme.cellW) - 2)))
                                            color: Theme.readable(quotaCard.modelData.percent >= 90 ? Theme.red : Theme.accent, Theme.panelSurfaceRaised, 4.5)
                                        }
                                        Line {
                                            width: parent.width
                                            text: root.resetText(quotaCard.modelData)
                                            color: Theme.fgDim
                                            font.pixelSize: Theme.fontCaption
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                            Repeater {
                                model: panel.tab === "tokens" ? (providerCard.modelData.stats?.models ?? []) : []
                                PanelRow {
                                    required property var modelData
                                    width: parent.width
                                    title: String(modelData.name || "Model")
                                    value: AiUsage.formatTokens(modelData.tokens)
                                }
                            }
                            Line {
                                width: parent.width
                                visible: panel.tab === "limits" ? !(providerCard.modelData.limits ?? []).length : !(providerCard.modelData.stats?.models ?? []).length
                                text: panel.tab === "limits" ? "Limits unavailable" : "No local token history"
                                color: Theme.fgDim
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
            Line {
                width: panel.rowWidth
                visible: !AiUsage.list.length
                text: AiUsage.discovering ? "Loading limits…" : "No usage data available. Try Refresh."
                color: Theme.fgDim
                wrapMode: Text.WordWrap
            }
            Line {
                width: panel.rowWidth
                text: "R refresh · E expand/collapse · Esc close"
                color: Theme.fgDim
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }
    }
}
