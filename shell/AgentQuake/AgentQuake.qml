import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// A drop-down command surface for persistent coding-agent sessions. An isolated
// tmux namespace owns the PTYs; nbshell owns discovery, selection, prompting
// and the visual workflow. No conversations are persisted in shell config.
PanelWindow {
    id: root

    property string selectedSession: ""
    property string selectedAgent: Agents.defaultAgent
    property string selectedProject: String(Agents.config.lastProject ?? "")
    property bool newSession: false
    property real reveal: 0
    property bool closing: false

    visible: Runtime.agentQuakeOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:agent-quake"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() {
        if (!visible || closing)
            return;
        closing = true;
        closeAnimation.restart();
    }
    function selectSession(id) {
        selectedSession = String(id);
        newSession = false;
        const row = selectedRow();
        if (String(row.status) === "stopped")
            Agents.sessionOutput = "This nbshell session is stopped. Select RESTORE to continue the latest conversation in its project.";
        else
            Agents.readSession(selectedSession);
    }
    function submit() {
        const prompt = composer.text.trim();
        if (prompt === "")
            return;
        if (newSession) {
            Agents.quakeStart(selectedAgent, selectedProject, prompt);
            composer.clear();
            refreshAfterStart.restart();
        } else if (selectedSession !== "") {
            Agents.promptSession(selectedSession, prompt);
            composer.clear();
            outputRefresh.restart();
        }
    }
    function statusColor(status) {
        const value = String(status);
        if (value === "working") return Theme.green;
        if (["blocked", "waiting", "permission"].indexOf(value) >= 0) return Theme.yellow;
        if (value === "done") return Theme.cyan;
        return Theme.fgDim;
    }
    function selectedRow() {
        return Agents.sessions.find(row => String(row.id) === selectedSession) ?? ({});
    }

    IpcHandler {
        target: "agentQuake"
        function toggle(): void { if (root.visible) root.close(); else Runtime.agentQuakeOpen = true; }
        function open(): void { if (!root.visible) Runtime.agentQuakeOpen = true; }
        function close(): void { root.close(); }
        function status(): string { return Runtime.agentQuakeOpen ? "open" : "closed"; }
    }

    onVisibleChanged: {
        if (visible) {
            reveal = 0;
            closing = false;
            Agents.acknowledgeCompletions();
            Agents.refresh();
            selectedProject = String(Agents.config.lastProject ?? "");
            if (selectedSession === "" && Agents.sessions.length > 0)
                selectSession(Agents.sessions[Agents.sessions.length - 1].id);
            Qt.callLater(() => {
                openAnimation.restart();
                composer.forceActiveFocus();
                outputView.scrollToEnd();
            });
        }
    }

    Connections {
        target: Agents
        function onSessionsChanged() {
            if (root.visible && !root.newSession && root.selectedSession === "" && Agents.sessions.length > 0)
                root.selectSession(Agents.sessions[Agents.sessions.length - 1].id);
        }
    }

    NumberAnimation { id: openAnimation; target: root; property: "reveal"; from: 0; to: 1; duration: 230; easing.type: Easing.OutCubic }
    NumberAnimation {
        id: closeAnimation
        target: root; property: "reveal"; to: 0; duration: 160; easing.type: Easing.InCubic
        onStopped: { Runtime.agentQuakeOpen = false; root.closing = false; }
    }

    Timer { id: outputRefresh; interval: 1200; repeat: false; onTriggered: Agents.readSession(root.selectedSession) }
    Timer { id: refreshAfterStart; interval: 2200; repeat: false; onTriggered: Agents.refresh() }
    Timer { interval: 5000; running: root.visible && root.selectedSession !== ""; repeat: true; onTriggered: { Agents.refresh(); if (String(root.selectedRow().status) !== "stopped") Agents.readSession(root.selectedSession); } }

    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bg, 0.52 * root.reveal) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) {
                Agents.refresh();
                Agents.readSession(root.selectedSession);
                event.accepted = true;
            }
        }

        PanelSurface {
            id: surface
            width: parent.width
            height: Math.min(parent.height * 0.68, Theme.cellH * 42)
            x: 0
            y: -height + root.reveal * height
            radius: 0
            accentBorder: true
            raised: true
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 1.6
                spacing: Theme.cellH * 0.55

                Item {
                    width: parent.width; height: Theme.cellH * 2
                    Line { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: Icons.cp(0xF1218) + "  AGENT CONSOLE"; color: Theme.fgBright; font.pixelSize: Theme.fontHeading; font.bold: true }
                    Line { anchors.centerIn: parent; text: Agents.workingCount + " WORKING  ·  " + Agents.waitingCount + " BLOCKED  ·  " + Agents.sessions.length + " SESSIONS  ·  " + String(Agents.sessionBackend.name).toUpperCase(); color: Agents.waitingCount > 0 ? Theme.yellow : Theme.fgDim }
                    Line { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "MOD+F1 / ESC  CLOSE"; color: Theme.muted }
                }
                Rule { rowWidth: parent.width; label: "PERSISTENT AGENT SESSIONS" }

                Row {
                    id: body
                    width: parent.width
                    height: parent.height - Theme.cellH * 5.4
                    spacing: Theme.cellW * 1.2

                    PanelSurface {
                        id: sessionsPanel
                        width: parent.width * 0.28
                        height: parent.height
                        accentBorder: false

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.cellW
                            spacing: Theme.cellH * 0.35
                            Item {
                                width: parent.width; height: Theme.cellH * 2
                                Line { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "SESSIONS"; color: Theme.fgDim; font.bold: true }
                                ActionButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "+ NEW"; compact: true; onTriggered: { root.newSession = true; root.selectedSession = ""; composer.forceActiveFocus(); } }
                            }
                            Line { visible: Agents.sessions.length === 0; width: parent.width; text: "No agent sessions yet"; color: Theme.muted; horizontalAlignment: Text.AlignHCenter }
                            Repeater {
                                model: Agents.sessions
                                Rectangle {
                                    id: sessionRow
                                    required property var modelData
                                    width: parent.width
                                    height: Theme.cellH * 3.1
                                    radius: Theme.radius
                                    color: root.selectedSession === String(modelData.id) ? Theme.selectedSurface(Theme.accent) : (sessionHover.hovered ? Theme.hover : "transparent")
                                    border.width: Theme.borderWidth
                                    border.color: root.selectedSession === String(modelData.id) ? Theme.focusBorder : root.statusColor(modelData.status)
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.top: parent.top; anchors.topMargin: Theme.cellH * 0.45; text: String(sessionRow.modelData.name).toUpperCase() + "  " + String(sessionRow.modelData.status).toUpperCase(); color: root.statusColor(sessionRow.modelData.status); font.bold: true }
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.cellH * 0.45; text: String(sessionRow.modelData.backend || "") + "  ·  " + (sessionRow.modelData.title || sessionRow.modelData.project || sessionRow.modelData.id); color: Theme.fgDim; elide: Text.ElideMiddle }
                                    HoverHandler { id: sessionHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.selectSession(sessionRow.modelData.id) }
                                }
                            }
                        }
                    }

                    PanelSurface {
                        id: outputPanel
                        width: parent.width * 0.43
                        height: parent.height
                        accentBorder: false
                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.cellW
                            spacing: Theme.cellH * 0.4
                            Item {
                                width: parent.width; height: Theme.cellH * 2
                                Line { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: root.newSession ? "NEW SESSION" : "RECENT TERMINAL OUTPUT"; color: Theme.fgDim; font.bold: true }
                                ActionButton { visible: !root.newSession && root.selectedSession !== ""; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: String(root.selectedRow().status) === "stopped" ? "RESTORE" : "FOCUS"; compact: true; onTriggered: { const id = root.selectedSession; if (String(root.selectedRow().status) === "stopped") Agents.restoreSession(id); else { root.close(); Qt.callLater(() => Agents.focusSession(id)); } } }
                            }
                            Flickable {
                                id: outputView
                                visible: !root.newSession
                                width: parent.width
                                height: parent.height - Theme.cellH * 2.5
                                clip: true
                                contentWidth: width
                                contentHeight: outputText.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                function scrollToEnd() { contentY = Math.max(0, contentHeight - height); }
                                onContentHeightChanged: Qt.callLater(scrollToEnd)
                                Line { id: outputText; width: parent.width; text: Agents.sessionOutput || (Agents.readingSession ? "Reading session …" : "Select a session to inspect its live output."); color: Theme.fg; wrapMode: Text.WrapAnywhere; font.pixelSize: Theme.fontCaption }
                            }
                            Column {
                                visible: root.newSession
                                width: parent.width
                                spacing: Theme.cellH * 0.55
                                Line { text: "AGENT"; color: Theme.muted }
                                Row {
                                    spacing: Theme.cellW
                                    Repeater {
                                        model: Agents.agents.filter(row => row.installed && ["codex", "claude", "agy"].indexOf(String(row.id)) >= 0)
                                        ActionButton { required property var modelData; text: modelData.name; compact: true; tone: root.selectedAgent === modelData.id ? "primary" : "neutral"; onTriggered: root.selectedAgent = modelData.id }
                                    }
                                }
                                Line { text: "PROJECT"; color: Theme.muted }
                                Repeater {
                                    model: Agents.projects.slice(0, 8)
                                    Rectangle {
                                        id: projectRow
                                        required property var modelData
                                        width: parent.width; height: Theme.cellH * 2
                                        radius: Theme.radius
                                        color: root.selectedProject === modelData.path ? Theme.selectedSurface(Theme.accent) : (projectHover.hovered ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth; border.color: root.selectedProject === modelData.path ? Theme.focusBorder : Theme.panelBorder
                                        Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: projectRow.modelData.name; color: Theme.fg }
                                        Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.65; text: projectRow.modelData.path; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle; color: Theme.fgDim }
                                        HoverHandler { id: projectHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.selectedProject = projectRow.modelData.path }
                                    }
                                }
                            }
                        }
                    }

                    PanelSurface {
                        width: parent.width - sessionsPanel.width - outputPanel.width - body.spacing * 2
                        height: parent.height
                        accentBorder: false
                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.cellW
                            spacing: Theme.cellH * 0.55
                            Line { text: root.newSession ? "FIRST COMMAND" : "NEXT COMMAND"; color: Theme.fgDim; font.bold: true }
                            QQC.TextArea {
                                id: composer
                                width: parent.width
                                height: parent.height - sendRow.height - Theme.cellH * 3.5
                                placeholderText: root.newSession ? "Describe the first task for the new agent…" : "Send the next task to this session…"
                                color: Theme.fg
                                placeholderTextColor: Theme.muted
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.selectedForeground(Theme.accent)
                                wrapMode: TextEdit.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontBody
                                padding: Theme.cellW
                                background: Rectangle { color: Theme.bgDark; radius: Theme.radius; border.width: Theme.borderWidth; border.color: composer.activeFocus ? Theme.focusBorder : Theme.panelBorder }
                                Keys.onPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        root.submit(); event.accepted = true;
                                    }
                                }
                            }
                            Row {
                                id: sendRow
                                width: parent.width
                                spacing: Theme.cellW
                                ActionButton { text: root.newSession ? "START " + root.selectedAgent.toUpperCase() : "SEND"; tone: "primary"; compact: true; enabled: composer.text.trim() !== "" && (root.newSession || root.selectedSession !== ""); onTriggered: root.submit() }
                                ActionButton { text: "CLEAR"; compact: true; onTriggered: composer.clear() }
                            }
                            Line { width: parent.width; text: "Ctrl+Enter sends  ·  F5 refreshes"; color: Theme.muted; horizontalAlignment: Text.AlignHCenter }
                        }
                    }
                }
            }
        }
    }
}
