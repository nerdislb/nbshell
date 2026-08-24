import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// One dense control surface for agents, models, projects, and live sessions.
// It follows Omarchy's panel hierarchy while retaining nbshell's TUI grid.
PanelWindow {
    id: root

    visible: Runtime.agentCenterOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:agents"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.agentCenterOpen = false; }

    onVisibleChanged: {
        if (visible) {
            Agents.refresh();
            keys.forceActiveFocus();
        }
    }

    IpcHandler {
        target: "agentCenter"
        function toggle(): void { Runtime.agentCenterOpen = !Runtime.agentCenterOpen; }
        function open(): void { Runtime.agentCenterOpen = true; }
        function close(): void { Runtime.agentCenterOpen = false; }
        function refresh(): void { Agents.refresh(); }
        function attention(kind: string, sessionId: string): void { Agents.requestAttention(kind, sessionId); }
        function attentionStatus(): string {
            return JSON.stringify({ "active": Agents.completionAttention, "sessions": Agents.attentionSessions });
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) { Agents.refresh(); event.accepted = true; }
        }

        OverlaySurface {
            preferredWidth: Theme.overlayWidthLarge
            preferredHeight: Theme.cellH * 44
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH * 0.55

                Row {
                    width: parent.width
                    spacing: Theme.cellW
                    Line {
                        width: parent.width - refreshLine.width - parent.spacing
                        text: Icons.cp(0xF1218) + "  AGENT CENTER"
                        color: Theme.fg
                        font.pixelSize: Theme.fontHeading
                        font.bold: true
                    }
                    Line {
                        id: refreshLine
                        text: Agents.loading ? "…" : "F5  REFRESH"
                        color: Theme.readable(Theme.accent, Theme.bg, 4.5)
                        font.pixelSize: Theme.fontCaption
                        TapHandler { onTapped: Agents.refresh() }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Theme.cellH * 3.3
                    radius: Theme.radius
                    color: Theme.panelSurfaceRaised
                    border.width: Theme.borderWidth
                    border.color: Theme.muted

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.cellW
                        spacing: Theme.cellW * 2
                        Column {
                            width: parent.width * 0.31
                            Line { text: "DEFAULT AGENT"; color: Theme.muted }
                            Line { text: Agents.defaultAgent.toUpperCase(); color: Theme.accent; font.pixelSize: Theme.fontTitle }
                        }
                        Column {
                            width: parent.width * 0.29
                            Line { text: "APPROVAL"; color: Theme.muted }
                            Line { text: Agents.approvalProfile.toUpperCase(); color: Agents.approvalProfile === "autonomous" ? Theme.yellow : Theme.fg; font.pixelSize: Theme.fontTitle }
                        }
                        Column {
                            width: parent.width * 0.31
                            Line { text: "MODEL PROFILE"; color: Theme.muted }
                            Line { text: Agents.modelProfile.toUpperCase(); color: Theme.fg; font.pixelSize: Theme.fontTitle }
                        }
                    }
                }

                Flickable {
                    width: parent.width
                    height: parent.height - Theme.cellH * 8.5
                    contentHeight: body.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: body
                        width: parent.width
                        spacing: Theme.cellH * 0.8

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.2
                            Line { text: "AGENTS"; color: Theme.fgDim }
                            Repeater {
                                model: Agents.agents
                                Rectangle {
                                    id: agentRow
                                    required property var modelData
                                    width: body.width
                                    height: Theme.cellH * 2
                                    radius: Theme.radius
                                    color: modelData.id === Agents.defaultAgent ? Theme.selectedSurface(Theme.accent)
                                        : (agentHover.hovered ? Theme.hover : "transparent")
                                    border.width: Theme.borderWidth
                                    border.color: modelData.id === Agents.defaultAgent ? Theme.focusBorder : Theme.panelBorder
                                    Rectangle { width: Theme.borderWidth * 2; height: parent.height * 0.55; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; color: agentRow.modelData.installed ? Theme.green : Theme.muted }
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 1.5; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.36; text: agentRow.modelData.name; color: agentRow.modelData.installed ? Theme.fg : Theme.muted; elide: Text.ElideRight }
                                    Line { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; text: agentRow.modelData.kind.toUpperCase(); color: Theme.fgDim }
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: !agentRow.modelData.installed ? "INSTALL…" : (agentRow.modelData.id === Agents.defaultAgent ? "DEFAULT · OPEN" : "SET DEFAULT · OPEN"); color: !agentRow.modelData.installed ? Theme.accent : (agentRow.modelData.id === Agents.defaultAgent ? Theme.accent : Theme.muted) }
                                    HoverHandler { id: agentHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onTapped: (point, button) => {
                                            if (!agentRow.modelData.installed) Agents.install(agentRow.modelData.id);
                                            else if (button === Qt.RightButton) Agents.setDefault(agentRow.modelData.id);
                                            else Agents.launch(agentRow.modelData.id, Agents.config.lastProject || "");
                                        }
                                    }
                                }
                            }
                            Line { text: "Left click opens · right click sets default"; color: Theme.muted }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.25
                            Line { text: "APPROVAL PROFILE"; color: Theme.fgDim }
                            Row {
                                spacing: Theme.cellW
                                Repeater {
                                    model: ["safe", "balanced", "autonomous"]
                                    Rectangle {
                                        id: approval
                                        required property string modelData
                                        width: (body.width - Theme.cellW * 2) / 3
                                        height: Theme.cellH * 2
                                        radius: Theme.radius
                                        color: modelData === Agents.approvalProfile ? Theme.selectedSurface(Theme.accent) : (approvalHover.hovered ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: modelData === Agents.approvalProfile ? Theme.focusBorder : Theme.panelBorder
                                        Line { anchors.centerIn: parent; text: approval.modelData.toUpperCase(); color: approval.modelData === Agents.approvalProfile ? Theme.selectedForeground(Theme.accent) : (approval.modelData === "autonomous" ? Theme.yellow : Theme.fg) }
                                        HoverHandler { id: approvalHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: Agents.setProfile(approval.modelData) }
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.25
                            Line { text: "MODEL ROUTING"; color: Theme.fgDim }
                            Flow {
                                width: parent.width
                                spacing: Theme.cellW
                                Repeater {
                                    model: ["local", "cloud", "private", "fast", "strong"]
                                    Rectangle {
                                        id: route
                                        required property string modelData
                                        width: (body.width - Theme.cellW * 4) / 5
                                        height: Theme.cellH * 2
                                        radius: Theme.radius
                                        color: modelData === Agents.modelProfile ? Theme.selectedSurface(Theme.accent) : (routeHover.hovered ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: modelData === Agents.modelProfile ? Theme.focusBorder : Theme.panelBorder
                                        Line { anchors.centerIn: parent; text: route.modelData.toUpperCase(); color: modelData === Agents.modelProfile ? Theme.selectedForeground(Theme.accent) : Theme.fg }
                                        HoverHandler { id: routeHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: Agents.setModelProfile(route.modelData) }
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.25
                            Line { text: "NEW WORKSPACE"; color: Theme.fgDim }
                            Row {
                                spacing: Theme.cellW
                                Repeater {
                                    model: [
                                        { "id": "dev", "label": "DEV", "hint": "editor · agent · terminal" },
                                        { "id": "review", "label": "REVIEW", "hint": "adds read-only review" },
                                        { "id": "pair", "label": "PAIR", "hint": "lead · local agent" }
                                    ]
                                    Rectangle {
                                        id: workspaceButton
                                        required property var modelData
                                        width: (body.width - Theme.cellW * 2) / 3
                                        height: Theme.cellH * 2.6
                                        radius: Theme.radius
                                        color: workspaceHover.hovered ? Theme.hover : "transparent"
                                        border.width: Theme.borderWidth
                                        border.color: Theme.muted
                                        Column {
                                            anchors.centerIn: parent
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: workspaceButton.modelData.label; color: Theme.accent }
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: workspaceButton.modelData.hint; color: Theme.muted }
                                        }
                                        HoverHandler { id: workspaceHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: Agents.workspace(workspaceButton.modelData.id, Agents.config.lastProject || "") }
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.2
                            Line { text: "LOCAL MODELS"; color: Theme.fgDim }
                            Rectangle {
                                width: body.width
                                height: Theme.cellH * 2.2
                                radius: Theme.radius
                                color: ollamaHover.hovered ? Theme.hover : Theme.panelSurfaceRaised
                                border.width: Theme.borderWidth
                                border.color: Agents.ollama.running ? Theme.green : Theme.muted
                                Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: "OLLAMA"; color: Agents.ollama.installed ? Theme.fg : Theme.muted }
                                Line { anchors.centerIn: parent; text: Agents.ollama.running ? ((Agents.ollama.models?.length ?? 0) + " MODELS") : (Agents.ollama.installed ? "STOPPED" : "NOT INSTALLED"); color: Agents.ollama.running ? Theme.green : Theme.muted }
                                Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: Agents.ollama.installed ? (Agents.ollama.running ? "STOP" : "START") : "OPTIONAL"; color: Theme.accent }
                                HoverHandler { id: ollamaHover; cursorShape: Agents.ollama.installed ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { enabled: Agents.ollama.installed; onTapped: Agents.ollamaAction(Agents.ollama.running ? "stop" : "start") }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.2
                            Line { text: "PROJECTS"; color: Theme.fgDim }
                            Repeater {
                                model: Agents.projects.slice(0, 12)
                                Rectangle {
                                    id: projectRow
                                    required property var modelData
                                    width: body.width
                                    height: Theme.cellH * 1.8
                                    radius: Theme.radius
                                    color: projectHover.hovered ? Theme.hover : "transparent"
                                    border.width: Theme.borderWidth
                                    border.color: String(Agents.config.lastProject || "") === modelData.path ? Theme.focusBorder : Theme.panelBorder
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: projectRow.modelData.name; color: Theme.fg }
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.65; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle; text: projectRow.modelData.path + "  ›"; color: Theme.fgDim }
                                    HoverHandler { id: projectHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Agents.launch("", projectRow.modelData.path) }
                                }
                            }
                        }

                        Column {
                            visible: Agents.sessions.length > 0
                            width: parent.width
                            spacing: Theme.cellH * 0.2
                            Line { text: "LIVE SESSIONS"; color: Theme.fgDim }
                            Repeater {
                                model: Agents.sessions
                                Rectangle {
                                    id: sessionRow
                                    required property var modelData
                                    width: body.width
                                    height: Theme.cellH * 1.8
                                    radius: Theme.radius
                                    color: sessionHover.hovered ? Theme.hover : "transparent"
                                    border.width: Theme.borderWidth
                                    border.color: ["waiting", "permission", "blocked"].indexOf(String(sessionRow.modelData.status)) >= 0 ? Theme.yellow : Theme.muted
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: sessionRow.modelData.name.toUpperCase() + "  " + sessionRow.modelData.status.toUpperCase(); color: ["waiting", "permission", "blocked"].indexOf(String(sessionRow.modelData.status)) >= 0 ? Theme.yellow : Theme.fg }
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.58; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle; text: sessionRow.modelData.title || sessionRow.modelData.project; color: Theme.fgDim }
                                    HoverHandler { id: sessionHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Agents.focusSession(sessionRow.modelData.id) }
                                }
                            }
                        }
                    }
                }

                Line {
                    width: parent.width
                    text: Agents.message !== "" ? Agents.message : "Esc closes · F5 refreshes · project click launches the default agent"
                    color: Agents.message !== "" ? Theme.yellow : Theme.muted
                    elide: Text.ElideRight
                }
            }
        }
    }
}
