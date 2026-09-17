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

    function metricValue(value) {
        const number = Number(value);
        return isFinite(number) ? Math.max(0, Math.min(100, Math.round(number))) : 0;
    }

    // Shared warning threshold; the dashboard uses the same role and value.
    function atWarning(value) {
        const number = Number(value);
        return isFinite(number) && number >= 90;
    }

    // Meter geometry is a display heuristic, not a layout token: one cell per
    // 1.2 character widths, clamped so a narrow popout still shows a readable
    // bar. Matches the approved quota dashboard (shell/Menu/WorkQuotas.qml).
    function meterCells(available) {
        return Math.max(8, Math.min(24, Math.floor(available / (Theme.cellW * 1.2))));
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
                                spacing: Theme.spaceXs
                                Line {
                                    width: parent.width
                                    text: (modelData.label || "Session") + " · " + root.percent(modelData.percent)
                                    color: root.atWarning(modelData.percent) ? Theme.readable(Theme.yellow, Theme.bg, 4.5) : Theme.fg
                                    elide: Text.ElideRight
                                }
                                LevelBar {
                                    value: root.metricValue(modelData.percent)
                                    interactive: false
                                    cells: root.meterCells(parent.width)
                                    fillColor: root.atWarning(modelData.percent) ? Theme.yellow : Theme.accent
                                }
                                Line {
                                    width: parent.width
                                    text: root.resetText(modelData)
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
            property Item initialFocusItem: refreshButton
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
            Segments {
                rowWidth: panel.rowWidth
                options: [
                    { label: "LIMITS", value: "limits" },
                    { label: "TOKEN USAGE", value: "tokens" }
                ]
                current: panel.tab
                onChosen: value => panel.tab = value
            }
            Flow {
                width: panel.rowWidth
                spacing: Theme.spaceSm
                ActionButton { id: refreshButton; text: "Refresh"; compact: true; onTriggered: AiUsage.refresh() }
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
                                Column {
                                    id: quotaBlock
                                    required property var modelData
                                    required property int index
                                    width: parent.width
                                    spacing: Theme.spaceXs
                                    Rule {
                                        rowWidth: quotaBlock.width
                                        visible: quotaBlock.index > 0
                                    }
                                    Item {
                                        width: parent.width
                                        height: Theme.cellH
                                        Line {
                                            width: parent.width - quotaPercent.implicitWidth - Theme.spaceSm
                                            text: quotaBlock.modelData.label || "Session"
                                            color: Theme.fgBright
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Line {
                                            id: quotaPercent
                                            anchors.right: parent.right
                                            text: root.percent(quotaBlock.modelData.percent)
                                            color: root.atWarning(quotaBlock.modelData.percent) ? Theme.readable(Theme.yellow, Theme.panelSurface, 4.5) : Theme.fgBright
                                            font.bold: true
                                        }
                                    }
                                    LevelBar {
                                        value: root.metricValue(quotaBlock.modelData.percent)
                                        interactive: false
                                        cells: root.meterCells(quotaBlock.width)
                                        fillColor: root.atWarning(quotaBlock.modelData.percent) ? Theme.yellow : Theme.accent
                                    }
                                    Line {
                                        width: parent.width
                                        text: root.resetText(quotaBlock.modelData)
                                        color: Theme.fgDim
                                        font.pixelSize: Theme.fontCaption
                                        wrapMode: Text.WordWrap
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
