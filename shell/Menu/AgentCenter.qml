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
    property string pendingJobAction: ""

    visible: Runtime.agentCenterOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:agents"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.agentCenterOpen = false; }
    function confirmJobAction(action, jobId) {
        const key = action + ":" + jobId;
        if (pendingJobAction !== key) {
            pendingJobAction = key;
            approvalReset.restart();
            return;
        }
        pendingJobAction = "";
        Agents.hermesJobAction(action, jobId, "");
    }
    function confirmTeamAction(action, teamId) {
        const key = "team-" + action + ":" + teamId;
        if (["apply", "install", "push", "reject"].includes(action) && pendingJobAction !== key) {
            pendingJobAction = key; approvalReset.restart(); return;
        }
        pendingJobAction = ""; Agents.hermesTeamAction(action, teamId);
    }
    function confirmBrainAction(action, proposalId) {
        const key = "brain-" + action + ":" + proposalId;
        if (pendingJobAction !== key) { pendingJobAction = key; approvalReset.restart(); return; }
        pendingJobAction = ""; Agents.hermesBrainAction(action, proposalId);
    }
    function compactTokens(value) {
        const count = Number(value || 0);
        return count >= 1000 ? (count / 1000).toFixed(count >= 10000 ? 0 : 1) + "k" : String(count);
    }
    function sessionTime(epoch) {
        if (!epoch) return "unknown";
        return new Date(Number(epoch) * 1000).toLocaleString(Qt.locale(), "dd.MM hh:mm");
    }

    onVisibleChanged: {
        if (visible) {
            Agents.refresh();
            keys.forceActiveFocus();
        }
    }

    Timer { id: approvalReset; interval: 6000; onTriggered: root.pendingJobAction = "" }

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
                            spacing: Theme.cellH * 0.3
                            visible: (Agents.brainProposals || []).length > 0
                            Line { text: "SECOND BRAIN PROPOSALS"; color: Theme.fgDim }
                            Line { text: "Isolated note · independent privacy review · human-only commit and push"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            Repeater {
                                model: (Agents.brainProposals || []).slice(0, 4)
                                Rectangle {
                                    id: brainRow
                                    required property var modelData
                                    width: body.width; height: Theme.cellH * 2.4; radius: Theme.radius
                                    color: String(modelData.id) === Agents.selectedBrainProposalId ? Theme.selectedSurface(Theme.accent) : (brainHover.hovered ? Theme.hover : "transparent")
                                    border.width: Theme.borderWidth; border.color: String(modelData.id) === Agents.selectedBrainProposalId ? Theme.focusBorder : Theme.panelBorder
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.48; text: String(brainRow.modelData.target); color: Theme.fg; elide: Text.ElideMiddle }
                                    Line { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; text: String(brainRow.modelData.author).toUpperCase() + " → " + String(brainRow.modelData.reviewer).toUpperCase(); color: Theme.fgDim }
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: String(brainRow.modelData.status).toUpperCase(); color: String(brainRow.modelData.status) === "awaiting_approval" ? Theme.green : (["failed","rejected","revision_requested"].includes(String(brainRow.modelData.status)) ? Theme.red : Theme.yellow) }
                                    HoverHandler { id: brainHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Agents.selectBrainProposal(brainRow.modelData.id) }
                                }
                            }
                            Rectangle {
                                width: body.width
                                height: brainDetail.implicitHeight + Theme.cellH * 2
                                visible: Boolean(Agents.brainProposalDetail && Agents.brainProposalDetail.id && Agents.brainProposalDetail.id === Agents.selectedBrainProposalId)
                                radius: Theme.radius; color: Theme.panelSurfaceRaised; border.width: Theme.borderWidth; border.color: Theme.panelBorder
                                Column {
                                    id: brainDetail
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.cellW
                                    spacing: Theme.cellH * 0.35
                                    Line { width: parent.width; text: "TARGET  " + String(Agents.brainProposalDetail.target || ""); color: Theme.fg; font.bold: true; elide: Text.ElideMiddle }
                                    Line { width: parent.width; text: String(Agents.brainProposalDetail.review || Agents.brainProposalDetail.error || "Independent review is running").slice(-2500); color: Agents.brainProposalDetail.error ? Theme.red : Theme.fgDim; wrapMode: Text.Wrap }
                                    Line { visible: Boolean(Agents.brainProposalDetail.can_revise); text: "REVISION REQUESTED · Ask Hermes to revise proposal " + String(Agents.brainProposalDetail.id || ""); color: Theme.yellow }
                                    Row {
                                        spacing: Theme.cellW
                                        Repeater {
                                            model: [
                                                {"id":"apply", "enabled":Boolean(Agents.brainProposalDetail.can_apply)},
                                                {"id":"push", "enabled":Boolean(Agents.brainProposalDetail.can_push)},
                                                {"id":"reject", "enabled":!["applied","pushed","rejected"].includes(String(Agents.brainProposalDetail.status))}
                                            ]
                                            Rectangle {
                                                id: brainAction
                                                required property var modelData
                                                width: (brainDetail.width - Theme.cellW * 2) / 3; height: Theme.cellH * 2; radius: Theme.radius
                                                opacity: modelData.enabled ? 1 : 0.32; color: brainActionHover.hovered && modelData.enabled ? Theme.hover : "transparent"
                                                border.width: Theme.borderWidth; border.color: modelData.enabled ? (modelData.id === "reject" ? Theme.red : Theme.accent) : Theme.panelBorder
                                                Line { anchors.centerIn: parent; text: root.pendingJobAction === "brain-" + brainAction.modelData.id + ":" + Agents.brainProposalDetail.id ? "CONFIRM" : String(brainAction.modelData.id).toUpperCase(); color: brainAction.modelData.id === "reject" ? Theme.red : Theme.fg }
                                                HoverHandler { id: brainActionHover; cursorShape: brainAction.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                                TapHandler { enabled: brainAction.modelData.enabled; onTapped: root.confirmBrainAction(brainAction.modelData.id, Agents.brainProposalDetail.id) }
                                            }
                                        }
                                    }
                                    Line { width: parent.width; visible: Boolean(Agents.brainProposalDetail.diff); text: String(Agents.brainProposalDetail.diff || "").slice(0, 12000); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; wrapMode: Text.WrapAnywhere }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.3
                            visible: (Agents.hermesTeams || []).length > 0
                            Line { text: "SUPERVISED TEAMS"; color: Theme.fgDim }
                            Line { text: "Parallel work · independent review · isolated integration · human approval"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            Repeater {
                                model: (Agents.hermesTeams || []).slice(0, 3)
                                Rectangle {
                                    id: teamRow
                                    required property var modelData
                                    width: body.width
                                    height: teamBody.implicitHeight + Theme.cellH * 1.5
                                    radius: Theme.radius
                                    color: Theme.panelSurfaceRaised
                                    border.width: Theme.borderWidth
                                    border.color: String(modelData.status) === "awaiting_approval" ? Theme.accent : Theme.panelBorder
                                    Column {
                                        id: teamBody
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.cellW
                                        spacing: Theme.cellH * 0.3
                                        Row {
                                            width: parent.width
                                            Line { width: parent.width * 0.66; text: String(teamRow.modelData.goal); color: Theme.fg; font.bold: true; elide: Text.ElideRight }
                                            Line { width: parent.width * 0.34; horizontalAlignment: Text.AlignRight; text: String(teamRow.modelData.status).toUpperCase() + " · " + Number(teamRow.modelData.progress || 0) + "% · " + Math.floor(Number(teamRow.modelData.elapsed || 0) / 60) + "M"; color: ["failed", "cancelled", "rejected"].includes(String(teamRow.modelData.status)) ? Theme.red : (String(teamRow.modelData.status) === "awaiting_approval" ? Theme.green : Theme.yellow) }
                                        }
                                        Rectangle { width: parent.width; height: Theme.borderWidth * 3; color: Theme.panelBorder; Rectangle { width: parent.width * Number(teamRow.modelData.progress || 0) / 100; height: parent.height; color: Theme.accent } }
                                        Repeater {
                                            model: teamRow.modelData.tasks || []
                                            Line { required property var modelData; width: teamBody.width; text: String(modelData.provider).toUpperCase() + "  " + String(modelData.title) + "  ·  " + String(modelData.status).toUpperCase() + "  ·  TRY " + Number(modelData.attempt || 0); color: modelData.status === "failed" ? Theme.red : Theme.fgDim; elide: Text.ElideRight }
                                        }
                                        Line { width: parent.width; text: String(teamRow.modelData.summary || teamRow.modelData.error || "Working"); color: teamRow.modelData.error ? Theme.red : Theme.muted; elide: Text.ElideRight }
                                        Row {
                                            spacing: Theme.cellW
                                            Repeater {
                                                model: [
                                                    {"id":"pause", "enabled":["running","reviewing","revising","integrating","testing"].includes(String(teamRow.modelData.status))},
                                                    {"id":"resume", "enabled":Boolean(teamRow.modelData.can_resume)},
                                                    {"id":"cancel", "enabled":!["applied","installed","pushed","cancelled","rejected"].includes(String(teamRow.modelData.status))},
                                                    {"id":"apply", "enabled":Boolean(teamRow.modelData.can_apply)},
                                                    {"id":"install", "enabled":Boolean(teamRow.modelData.can_install)},
                                                    {"id":"push", "enabled":Boolean(teamRow.modelData.can_push)}
                                                ]
                                                Rectangle {
                                                    id: teamAction
                                                    required property var modelData
                                                    width: (teamBody.width - Theme.cellW * 5) / 6; height: Theme.cellH * 1.8; radius: Theme.radius
                                                    opacity: modelData.enabled ? 1 : 0.32; color: teamActionHover.hovered && modelData.enabled ? Theme.hover : "transparent"
                                                    border.width: Theme.borderWidth; border.color: modelData.enabled ? Theme.accent : Theme.panelBorder
                                                    Line { anchors.centerIn: parent; text: root.pendingJobAction === "team-" + teamAction.modelData.id + ":" + teamRow.modelData.id ? "CONFIRM" : String(teamAction.modelData.id).toUpperCase(); color: Theme.fg; font.pixelSize: Theme.fontCaption }
                                                    HoverHandler { id: teamActionHover; cursorShape: teamAction.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                                    TapHandler { enabled: teamAction.modelData.enabled; onTapped: root.confirmTeamAction(teamAction.modelData.id, teamRow.modelData.id) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.3
                            visible: (Agents.hermesJobs || []).length > 0
                            Line { text: "HERMES TRANSACTIONS"; color: Theme.fgDim }
                            Line { text: "Agents work in disposable clones · review and human approval are mandatory"; color: Theme.muted; font.pixelSize: Theme.fontCaption }

                            Repeater {
                                model: (Agents.hermesJobs || []).slice(0, 5)
                                Rectangle {
                                    id: transactionRow
                                    required property var modelData
                                    width: body.width
                                    height: Theme.cellH * 2.3
                                    radius: Theme.radius
                                    color: String(modelData.id) === Agents.selectedJobId ? Theme.selectedSurface(Theme.accent) : (transactionHover.hovered ? Theme.hover : "transparent")
                                    border.width: Theme.borderWidth
                                    border.color: String(modelData.id) === Agents.selectedJobId ? Theme.focusBorder : Theme.panelBorder
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.2; text: String(transactionRow.modelData.provider).toUpperCase(); color: Theme.accent }
                                    Line { anchors.centerIn: parent; width: parent.width * 0.45; text: String(transactionRow.modelData.task); elide: Text.ElideRight; color: Theme.fg }
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: String(transactionRow.modelData.status).toUpperCase(); color: ["failed", "rejected"].includes(String(transactionRow.modelData.status)) ? Theme.red : (["reviewed", "applied", "installed", "pushed"].includes(String(transactionRow.modelData.status)) ? Theme.green : Theme.yellow) }
                                    HoverHandler { id: transactionHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: Agents.selectHermesJob(transactionRow.modelData.id) }
                                }
                            }

                            Rectangle {
                                width: body.width
                                height: transactionDetail.implicitHeight + Theme.cellH * 2
                                visible: Boolean(Agents.jobDetail && Agents.jobDetail.id && Agents.jobDetail.id === Agents.selectedJobId)
                                radius: Theme.radius
                                color: Theme.panelSurfaceRaised
                                border.width: Theme.borderWidth
                                border.color: Theme.panelBorder

                                Column {
                                    id: transactionDetail
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.cellW
                                    spacing: Theme.cellH * 0.35
                                    Line { width: parent.width; text: "JOB " + String(Agents.jobDetail.id || ""); color: Theme.fg; font.bold: true; elide: Text.ElideRight }
                                    Line { width: parent.width; text: String(Agents.jobDetail.summary || Agents.jobDetail.error || "Waiting for agent output"); color: Agents.jobDetail.error ? Theme.red : Theme.fgDim; wrapMode: Text.Wrap }
                                    Line { text: "REVIEW: " + ((Agents.jobDetail.reviews || []).length ? String(Agents.jobDetail.reviews[Agents.jobDetail.reviews.length - 1].provider).toUpperCase() + " · " + String(Agents.jobDetail.reviews[Agents.jobDetail.reviews.length - 1].status).toUpperCase() : "PENDING"); color: (Agents.jobDetail.reviews || []).some(row => row.status === "approved") ? Theme.green : Theme.yellow }

                                    Row {
                                        spacing: Theme.cellW
                                        visible: Boolean(Agents.jobDetail.can_review)
                                        Repeater {
                                            model: ["codex", "claude", "gemini"].filter(name => name !== Agents.jobDetail.provider)
                                            Rectangle {
                                                id: reviewerButton
                                                required property string modelData
                                                width: (transactionDetail.width - Theme.cellW) / 2
                                                height: Theme.cellH * 2
                                                radius: Theme.radius
                                                color: reviewerHover.hovered ? Theme.hover : "transparent"
                                                border.width: Theme.borderWidth
                                                border.color: Theme.panelBorder
                                                Line { anchors.centerIn: parent; text: "REVIEW WITH " + reviewerButton.modelData.toUpperCase(); color: Theme.accent }
                                                HoverHandler { id: reviewerHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler { onTapped: Agents.hermesJobAction("review", Agents.jobDetail.id, reviewerButton.modelData) }
                                            }
                                        }
                                    }

                                    Row {
                                        spacing: Theme.cellW
                                        Repeater {
                                            model: [
                                                { "id": "apply", "label": "APPLY", "enabled": Boolean(Agents.jobDetail.can_apply) },
                                                { "id": "install", "label": "INSTALL", "enabled": Boolean(Agents.jobDetail.can_install) },
                                                { "id": "push", "label": "PUSH", "enabled": Boolean(Agents.jobDetail.can_push) },
                                                { "id": "reject", "label": "REJECT", "enabled": !["applied", "installed", "pushed", "rejected"].includes(String(Agents.jobDetail.status)) }
                                            ]
                                            Rectangle {
                                                id: transactionAction
                                                required property var modelData
                                                width: (transactionDetail.width - Theme.cellW * 3) / 4
                                                height: Theme.cellH * 2
                                                radius: Theme.radius
                                                color: root.pendingJobAction === modelData.id + ":" + Agents.jobDetail.id ? Theme.yellow : (transactionActionHover.hovered && modelData.enabled ? Theme.hover : "transparent")
                                                opacity: modelData.enabled ? 1 : 0.35
                                                border.width: Theme.borderWidth
                                                border.color: modelData.enabled ? (modelData.id === "reject" ? Theme.red : Theme.accent) : Theme.panelBorder
                                                Line { anchors.centerIn: parent; text: root.pendingJobAction === transactionAction.modelData.id + ":" + Agents.jobDetail.id ? "CONFIRM" : transactionAction.modelData.label; color: root.pendingJobAction === transactionAction.modelData.id + ":" + Agents.jobDetail.id ? Theme.bg : (transactionAction.modelData.id === "reject" ? Theme.red : Theme.fg) }
                                                HoverHandler { id: transactionActionHover; cursorShape: transactionAction.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                                TapHandler { enabled: transactionAction.modelData.enabled; onTapped: root.confirmJobAction(transactionAction.modelData.id, Agents.jobDetail.id) }
                                            }
                                        }
                                    }

                                    Line {
                                        width: parent.width
                                        visible: Boolean(Agents.jobDetail.diff)
                                        text: String(Agents.jobDetail.diff || "").slice(0, 12000)
                                        color: Theme.fgDim
                                        font.pixelSize: Theme.fontCaption
                                        wrapMode: Text.WrapAnywhere
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.4
                            Line { text: "HERMES HUB"; color: Theme.fgDim }
                            Rectangle {
                                width: body.width
                                height: Theme.cellH * 3
                                radius: Theme.radius
                                color: hermesHover.hovered ? Theme.hover : Theme.panelSurfaceRaised
                                border.width: Theme.borderWidth
                                border.color: Agents.hermes.authenticated ? Theme.green : Theme.muted
                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.cellW
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    Line { text: "HERMES  " + (Agents.hermes.version || "NOT INSTALLED"); color: Agents.hermes.installed ? Theme.fg : Theme.muted }
                                    Line { text: Agents.hermesProvider.toUpperCase() + " · " + Agents.hermesMode.toUpperCase(); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight; width: body.width * 0.68 }
                                }
                                Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: Agents.hermes.gateway === "active" ? "GATEWAY ACTIVE" : (Agents.hermes.running ? "OPEN · ACTIVE" : "OPEN"); color: Agents.hermes.gateway === "active" ? Theme.yellow : Theme.accent }
                                HoverHandler { id: hermesHover; cursorShape: Agents.hermes.installed ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler {
                                    enabled: Agents.hermes.installed
                                    onTapped: {
                                        Agents.launch("hermes", "");
                                        root.close();
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.cellW
                                Repeater {
                                    model: [
                                        { "id": "codex", "label": "CODEX", "hint": "native" },
                                        { "id": "claude", "label": "CLAUDE", "hint": "native" },
                                        { "id": "gemini", "label": "GEMINI", "hint": "agy bridge" }
                                    ]
                                    Rectangle {
                                        id: hermesProviderButton
                                        required property var modelData
                                        readonly property var providerState: (Agents.hermes.providers || {})[modelData.id] || ({ "ready": false })
                                        width: (body.width - Theme.cellW * 2) / 3
                                        height: Theme.cellH * 2.6
                                        radius: Theme.radius
                                        color: modelData.id === Agents.hermesProvider ? Theme.selectedSurface(Theme.accent) : (hermesProviderHover.hovered ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: modelData.id === Agents.hermesProvider ? Theme.focusBorder : Theme.panelBorder
                                        Column {
                                            anchors.centerIn: parent
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesProviderButton.modelData.label; color: hermesProviderButton.providerState.ready ? Theme.fg : Theme.muted }
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesProviderButton.providerState.ready ? hermesProviderButton.modelData.hint : "not ready"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                                        }
                                        HoverHandler { id: hermesProviderHover; cursorShape: hermesProviderButton.providerState.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        TapHandler { enabled: hermesProviderButton.providerState.ready; onTapped: Agents.setHermesProvider(hermesProviderButton.modelData.id) }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.cellW
                                Repeater {
                                    model: [
                                        { "id": "restricted", "label": "RESTRICTED", "hint": "workspace files" },
                                        { "id": "research", "label": "RESEARCH", "hint": "+ read-only web" },
                                        { "id": "workspace", "label": "WORKSPACE", "hint": "pilot + terminal" },
                                        { "id": "trusted", "label": "TRUSTED", "hint": "project + YOLO" }
                                    ]
                                    Rectangle {
                                        id: hermesModeButton
                                        required property var modelData
                                        width: (body.width - Theme.cellW * 3) / 4
                                        height: Theme.cellH * 2.6
                                        radius: Theme.radius
                                        color: modelData.id === Agents.hermesMode ? Theme.selectedSurface(Theme.accent) : (hermesModeHover.hovered ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: modelData.id === Agents.hermesMode ? Theme.focusBorder : Theme.panelBorder
                                        Column {
                                            anchors.centerIn: parent
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesModeButton.modelData.label; color: ["workspace", "trusted"].includes(hermesModeButton.modelData.id) ? Theme.yellow : Theme.fg }
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesModeButton.modelData.hint; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                                        }
                                        HoverHandler { id: hermesModeHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: Agents.setHermesMode(hermesModeButton.modelData.id) }
                                    }
                                }
                            }

                            Line { text: Agents.hermesMode === "trusted" ? "Trusted is fully autonomous in the selected Git project · commands do not ask for approval" : (Agents.hermesProvider === "gemini" ? "Gemini: Restricted/Research use plan mode · Workspace accepts edits in its sandbox" : "Native Hermes lane · credentials stay in the provider-owned store"); color: Agents.hermesMode === "trusted" ? Theme.red : Theme.muted }

                            Column {
                                width: parent.width
                                spacing: Theme.cellH * 0.2
                                visible: Agents.hermesProvider !== "gemini" && (Agents.hermes.sessions || []).length > 0
                                Line { text: "RECENT HERMES SESSIONS"; color: Theme.fgDim }
                                Repeater {
                                    model: (Agents.hermes.sessions || []).slice(0, 3)
                                    Rectangle {
                                        id: hermesSession
                                        required property var modelData
                                        width: body.width
                                        height: Theme.cellH * 2
                                        radius: Theme.radius
                                        color: hermesSessionHover.hovered ? Theme.hover : "transparent"
                                        border.width: Theme.borderWidth
                                        border.color: Theme.panelBorder
                                        Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.42; text: String(hermesSession.modelData.id).slice(-8); color: Theme.fg }
                                        Line { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; text: root.sessionTime(hermesSession.modelData.lastActive); color: Theme.fgDim }
                                        Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: root.compactTokens(hermesSession.modelData.inputTokens + hermesSession.modelData.outputTokens) + " TOK · RESUME"; color: Theme.accent }
                                        HoverHandler { id: hermesSessionHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                Agents.resumeHermes(hermesSession.modelData.id);
                                                root.close();
                                            }
                                        }
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
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.65; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle; text: projectRow.modelData.path + "  ·  RIGHT HERMES"; color: Theme.fgDim }
                                    HoverHandler { id: projectHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onTapped: (point, button) => {
                                            Agents.launch(button === Qt.RightButton ? "hermes" : "", projectRow.modelData.path);
                                            root.close();
                                        }
                                    }
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
                    text: Agents.message !== "" ? Agents.message : "Esc closes · F5 refreshes · project: left default agent · right Hermes"
                    color: Agents.message !== "" ? Theme.yellow : Theme.muted
                    elide: Text.ElideRight
                }
            }
        }
    }
}
