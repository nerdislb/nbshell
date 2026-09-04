import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Widgets/FocusScroll.js" as FocusScroll

// A scan-first agent overview with detailed work and configuration kept on
// separate pages. It follows Omarchy's hierarchy and nbshell's TUI grid.
PanelWindow {
    id: root
    property string pendingJobAction: ""
    property int page: 0

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:agents"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.agentCenterOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.agentCenterOpen = false; }
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }
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
        if (["apply", "install", "push", "reject", "cancel"].includes(action) && pendingJobAction !== key) {
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
    function hermesCurrentSession() {
        const rows = Agents.hermes.sessions || [];
        return rows.find(row => Boolean(row.active)) || (rows.length ? rows[0] : ({}));
    }
    function shortPath(path) {
        const value = String(path || "");
        const home = Quickshell.env("HOME");
        return home && value.indexOf(home) === 0 ? "~" + value.slice(home.length) : value;
    }

    function revealFocusedItem(item) {
        if (!item || !agentFlick.visible)
            return;
        const mapped = item.mapToItem(body, 0, 0);
        agentFlick.contentY = FocusScroll.contentYForFocus(
            mapped.y, item.height, agentFlick.contentY, agentFlick.height,
            agentFlick.contentHeight, Theme.spaceMd);
    }
    function focusPageTab(index) {
        Qt.callLater(() => {
            const tab = pageTabs.itemAt(index);
            if (tab && tab.visible && tab.enabled)
                tab.forceActiveFocus(Qt.ShortcutFocusReason);
        });
    }
    function selectPage(index, focusTab) {
        page = Math.max(0, Math.min(2, index));
        if (focusTab)
            focusPageTab(page);
    }
    function money(value) {
        const amount = Number(value || 0);
        return amount > 0 ? "$" + amount.toFixed(amount >= 10 ? 2 : 4) : "INCLUDED";
    }

    onVisibleChanged: if (visible) {
        page = 0;
        keys.forceActiveFocus();
        focusPageTab(page);
    }
    onPageChanged: agentFlick.contentY = 0

    Connections {
        target: Runtime
        function onAgentCenterOpenChanged() {
            Agents.setOverviewVisible(Runtime.agentCenterOpen);
        }
    }
    Component.onCompleted: Agents.setOverviewVisible(Runtime.agentCenterOpen)
    Component.onDestruction: Agents.setOverviewVisible(false)

    Timer { id: approvalReset; interval: 6000; onTriggered: root.pendingJobAction = "" }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity * 0.45 }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) { Agents.refresh(); event.accepted = true; }
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
                root.selectPage(event.key - Qt.Key_1, true);
                event.accepted = true;
            }
        }

        OverlaySurface {
            id: box
            dockedTop: true
            preferredWidth: Theme.cellW * 112
            preferredHeight: Theme.cellH * 32
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
                        text: Icons.cp(0xF1218) + "  AGENTS  ·  "
                            + Agents.hermesProvider.toUpperCase() + "  ·  "
                            + Agents.hermesMode.toUpperCase()
                        color: Theme.fg
                        font.pixelSize: Theme.fontHeading
                        font.bold: true
                    }
                    ActionButton {
                        id: refreshLine
                        text: "REFRESH"
                        compact: true
                        busy: Agents.loading
                        accessibleDescription: "Refresh agent and Hermes status"
                        onTriggered: Agents.refresh()
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.cellW
                    Repeater {
                        id: pageTabs
                        model: ["NOW", "WORK", "SETUP"]
                        ControlButton {
                            required property string modelData
                            required property int index
                            width: (parent.width - Theme.cellW * 2) / 3
                            height: Theme.cellH * 1.7
                            text: modelData
                            selected: root.page === index
                            onTriggered: root.selectPage(index, false)
                        }
                    }
                }

                Flickable {
                    id: agentFlick
                    width: parent.width
                    height: parent.height - Theme.cellH * 6.6
                    contentHeight: body.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: body
                        width: parent.width
                        spacing: Theme.cellH * 0.8

                        Column {
                            visible: root.page === 2
                            width: parent.width
                            spacing: Theme.cellH * 0.2
                            Line { text: "AGENTS"; color: Theme.fgDim }
                            Repeater {
                                model: Agents.agents
                                Item {
                                    id: agentEntry
                                    required property var modelData
                                    width: body.width
                                    height: Theme.cellH * 2

                                    InteractiveSurface {
                                        id: agentRow
                                        property var modelData: agentEntry.modelData
                                        accessibleName: modelData.name
                                        accessibleDescription: modelData.installed ? "Open " + modelData.name : "Install " + modelData.name
                                        accessibleSelected: modelData.id === Agents.defaultAgent
                                        width: defaultAgentButton.visible
                                            ? parent.width - defaultAgentButton.width - Theme.spaceSm
                                            : parent.width
                                        height: parent.height
                                        radius: Theme.radius
                                        color: modelData.id === Agents.defaultAgent ? Theme.selectedSurface(Theme.accent)
                                            : (agentHover.hovered || visualFocus ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: modelData.id === Agents.defaultAgent || visualFocus ? Theme.focusBorder : Theme.panelBorder
                                        onTriggered: {
                                            if (!modelData.installed)
                                                Agents.install(modelData.id);
                                            else
                                                Agents.launch(modelData.id, Agents.config.lastProject || "");
                                        }
                                        onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(agentRow)
                                        Rectangle { width: Theme.borderWidth * 2; height: parent.height * 0.55; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; color: agentRow.modelData.installed ? Theme.green : Theme.muted }
                                        Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW * 1.5; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.36; text: agentRow.modelData.name; color: agentRow.modelData.installed ? Theme.fg : Theme.muted; elide: Text.ElideRight }
                                        Line { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; text: agentRow.modelData.kind.toUpperCase(); color: Theme.fgDim }
                                        Line { visible: !agentRow.modelData.installed || agentRow.modelData.id === Agents.defaultAgent; anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: !agentRow.modelData.installed ? "INSTALL…" : "DEFAULT · OPEN"; color: Theme.accent }
                                        HoverHandler { id: agentHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onTapped: (point, button) => {
                                                agentRow.forceActiveFocus(Qt.MouseFocusReason);
                                                if (button === Qt.RightButton && agentRow.modelData.installed)
                                                    Agents.setDefault(agentRow.modelData.id);
                                                else
                                                    agentRow.activate();
                                            }
                                        }
                                    }

                                    ActionButton {
                                        id: defaultAgentButton
                                        visible: agentEntry.modelData.installed && agentEntry.modelData.id !== Agents.defaultAgent
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "SET DEFAULT"
                                        compact: true
                                        accessibleDescription: "Set " + agentEntry.modelData.name + " as the default agent"
                                        onTriggered: {
                                            agentRow.forceActiveFocus(Qt.OtherFocusReason);
                                            Agents.setDefault(agentEntry.modelData.id);
                                        }
                                        onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(defaultAgentButton)
                                    }
                                }
                            }
                            Line { text: "Enter opens · Set Default is a separate action"; color: Theme.muted }
                        }

                        Column {
                            visible: root.page === 2
                            width: parent.width
                            spacing: Theme.cellH * 0.25
                            Line { text: "APPROVAL PROFILE"; color: Theme.fgDim }
                            Row {
                                spacing: Theme.cellW
                                Repeater {
                                    model: ["safe", "balanced", "autonomous"]
                                    ControlButton {
                                        id: approval
                                        required property string modelData
                                        width: (body.width - Theme.cellW * 2) / 3
                                        height: Theme.cellH * 2
                                        text: modelData.toUpperCase()
                                        selected: modelData === Agents.approvalProfile
                                        textColor: modelData === "autonomous" ? Theme.yellow : Theme.fg
                                        accessibleDescription: "Use the " + modelData + " approval profile"
                                        onTriggered: Agents.setProfile(modelData)
                                        onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(approval)
                                    }
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.cellH * 0.3
                            visible: root.page === 1 && (Agents.brainProposals || []).length > 0
                            Line { text: "SECOND BRAIN PROPOSALS"; color: Theme.fgDim }
                            Line { text: "Isolated note · independent privacy review · human-only commit and push"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                            Repeater {
                                model: (Agents.brainProposals || []).slice(0, 4)
                                InteractiveSurface {
                                    id: brainRow
                                    required property var modelData
                                    accessibleName: String(modelData.target)
                                    accessibleDescription: String(modelData.author) + " reviewed by " + String(modelData.reviewer) + ", status " + String(modelData.status)
                                    accessibleSelected: String(modelData.id) === Agents.selectedBrainProposalId
                                    width: body.width; height: Theme.cellH * 2.4; radius: Theme.radius
                                    color: String(modelData.id) === Agents.selectedBrainProposalId ? Theme.selectedSurface(Theme.accent) : (brainHover.hovered || visualFocus ? Theme.hover : "transparent")
                                    border.width: Theme.borderWidth; border.color: String(modelData.id) === Agents.selectedBrainProposalId || visualFocus ? Theme.focusBorder : Theme.panelBorder
                                    onTriggered: Agents.selectBrainProposal(modelData.id)
                                    onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(brainRow)
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.48; text: String(brainRow.modelData.target); color: Theme.fg; elide: Text.ElideMiddle }
                                    Line { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; text: String(brainRow.modelData.author).toUpperCase() + " → " + String(brainRow.modelData.reviewer).toUpperCase(); color: Theme.fgDim }
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: String(brainRow.modelData.status).toUpperCase(); color: String(brainRow.modelData.status) === "awaiting_approval" ? Theme.green : (["failed","rejected","revision_requested"].includes(String(brainRow.modelData.status)) ? Theme.red : Theme.yellow) }
                                    HoverHandler { id: brainHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { brainRow.forceActiveFocus(Qt.MouseFocusReason); brainRow.activate(); } }
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
                                            ControlButton {
                                                id: brainAction
                                                required property var modelData
                                                width: (brainDetail.width - Theme.cellW * 2) / 3; height: Theme.cellH * 2
                                                enabled: modelData.enabled
                                                danger: modelData.id === "reject"
                                                text: root.pendingJobAction === "brain-" + modelData.id + ":" + Agents.brainProposalDetail.id ? "CONFIRM" : String(modelData.id).toUpperCase()
                                                accessibleDescription: String(modelData.id) + " brain proposal " + Agents.brainProposalDetail.id
                                                onTriggered: root.confirmBrainAction(modelData.id, Agents.brainProposalDetail.id)
                                                onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(brainAction)
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
                            visible: root.page === 1 && (Agents.hermesTeams || []).length > 0
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
                                                ControlButton {
                                                    id: teamAction
                                                    required property var modelData
                                                    width: (teamBody.width - Theme.cellW * 5) / 6; height: Theme.cellH * 1.8
                                                    enabled: modelData.enabled
                                                    danger: modelData.id === "cancel"
                                                    text: root.pendingJobAction === "team-" + modelData.id + ":" + teamRow.modelData.id ? "CONFIRM" : String(modelData.id).toUpperCase()
                                                    accessibleDescription: String(modelData.id) + " supervised team " + teamRow.modelData.id
                                                    onTriggered: root.confirmTeamAction(modelData.id, teamRow.modelData.id)
                                                    onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(teamAction)
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
                            visible: root.page === 1 && (Agents.hermesJobs || []).length > 0
                            Line { text: "HERMES TRANSACTIONS"; color: Theme.fgDim }
                            Line { text: "Agents work in disposable clones · review and human approval are mandatory"; color: Theme.muted; font.pixelSize: Theme.fontCaption }

                            Repeater {
                                model: (Agents.hermesJobs || []).slice(0, 5)
                                InteractiveSurface {
                                    id: transactionRow
                                    required property var modelData
                                    accessibleName: String(modelData.provider).toUpperCase() + " job"
                                    accessibleDescription: String(modelData.task) + ", status " + String(modelData.status)
                                    accessibleSelected: String(modelData.id) === Agents.selectedJobId
                                    width: body.width
                                    height: Theme.cellH * 2.3
                                    radius: Theme.radius
                                    color: String(modelData.id) === Agents.selectedJobId ? Theme.selectedSurface(Theme.accent) : (transactionHover.hovered || visualFocus ? Theme.hover : "transparent")
                                    border.width: Theme.borderWidth
                                    border.color: String(modelData.id) === Agents.selectedJobId || visualFocus ? Theme.focusBorder : Theme.panelBorder
                                    onTriggered: Agents.selectHermesJob(modelData.id)
                                    onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(transactionRow)
                                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.2; text: String(transactionRow.modelData.provider).toUpperCase(); color: Theme.accent }
                                    Line { anchors.centerIn: parent; width: parent.width * 0.45; text: String(transactionRow.modelData.task); elide: Text.ElideRight; color: Theme.fg }
                                    Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: String(transactionRow.modelData.status).toUpperCase(); color: ["failed", "rejected"].includes(String(transactionRow.modelData.status)) ? Theme.red : (["reviewed", "applied", "installed", "pushed"].includes(String(transactionRow.modelData.status)) ? Theme.green : Theme.yellow) }
                                    HoverHandler { id: transactionHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { transactionRow.forceActiveFocus(Qt.MouseFocusReason); transactionRow.activate(); } }
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
                                            ControlButton {
                                                id: reviewerButton
                                                required property string modelData
                                                width: (transactionDetail.width - Theme.cellW) / 2
                                                height: Theme.cellH * 2
                                                text: "REVIEW WITH " + modelData.toUpperCase()
                                                accessibleDescription: "Review this job with " + modelData
                                                onTriggered: Agents.hermesJobAction("review", Agents.jobDetail.id, modelData)
                                                onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(reviewerButton)
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
                                            ControlButton {
                                                id: transactionAction
                                                required property var modelData
                                                width: (transactionDetail.width - Theme.cellW * 3) / 4
                                                height: Theme.cellH * 2
                                                enabled: modelData.enabled
                                                danger: modelData.id === "reject"
                                                selected: root.pendingJobAction === modelData.id + ":" + Agents.jobDetail.id
                                                text: selected ? "CONFIRM" : modelData.label
                                                accessibleDescription: modelData.label + " job " + Agents.jobDetail.id
                                                onTriggered: root.confirmJobAction(modelData.id, Agents.jobDetail.id)
                                                onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(transactionAction)
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

                        Line {
                            visible: root.page === 1
                                && (Agents.brainProposals || []).length === 0
                                && (Agents.hermesTeams || []).length === 0
                                && (Agents.hermesJobs || []).length === 0
                            width: parent.width
                            text: "No active jobs, teams, or proposals"
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.muted
                        }

                        Column {
                            visible: root.page !== 1
                            width: parent.width
                            spacing: Theme.cellH * 0.4
                            Line { text: root.page === 0 ? "CURRENT SESSION" : "HERMES"; color: Theme.fgDim }

                            Rectangle {
                                visible: root.page === 0
                                width: body.width
                                height: visible ? hermesOverview.implicitHeight + Theme.cellH * 2 : 0
                                radius: Theme.radius
                                color: Theme.panelSurfaceRaised
                                border.width: Theme.borderWidth
                                border.color: Agents.hermes.running ? Theme.focusBorder : Theme.panelBorder

                                Column {
                                    id: hermesOverview
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.cellW
                                    spacing: Theme.cellH * 0.45
                                    readonly property var current: root.hermesCurrentSession()
                                    readonly property var today: (Agents.hermes.usage || {}).today || ({})
                                    readonly property int activeJobs: Number(Agents.hermes.jobsRunning || 0)
                                    readonly property int activeTeams: Number(Agents.hermes.teamsRunning || 0)
                                    readonly property int activeProposals: Number(Agents.hermes.brainReviewing || 0)

                                    Row {
                                        width: parent.width
                                        spacing: Theme.cellW
                                        Line { width: parent.width - activityBadge.width - openHermes.width - parent.spacing * 2; text: "HERMES"; color: Theme.fg; font.bold: true }
                                        Line {
                                            id: activityBadge
                                            text: hermesOverview.current.active ? "● WORKING" : (Agents.hermes.running ? "● READY" : "○ OFFLINE")
                                            color: hermesOverview.current.active ? Theme.yellow : (Agents.hermes.running ? Theme.green : Theme.muted)
                                        }
                                        ControlButton {
                                            id: openHermes
                                            width: Theme.cellW * 18
                                            height: Theme.cellH * 1.7
                                            text: hermesOverview.current.active ? "OPEN SESSION" : "OPEN HERMES"
                                            enabled: Agents.hermes.installed
                                            onTriggered: {
                                                root.close();
                                                Agents.openHermes(hermesOverview.current.id || "");
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: 0
                                        Line { width: parent.width; text: String(hermesOverview.current.title || "No recent Hermes session"); color: Theme.fg; font.pixelSize: Theme.fontTitle; elide: Text.ElideRight }
                                        Line {
                                            width: parent.width
                                            text: root.shortPath(hermesOverview.current.cwd) + (hermesOverview.current.activity ? "  ·  " + String(hermesOverview.current.activity).toUpperCase() : "")
                                            color: hermesOverview.current.active ? Theme.accent : Theme.fgDim
                                            font.pixelSize: Theme.fontCaption
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        spacing: Theme.cellW
                                        Repeater {
                                            model: [
                                                { "label": "SESSION", "value": root.compactTokens(Number(hermesOverview.current.inputTokens || 0) + Number(hermesOverview.current.outputTokens || 0)), "hint": "TOKENS" },
                                                { "label": "TODAY", "value": root.compactTokens(Number(hermesOverview.today.inputTokens || 0) + Number(hermesOverview.today.outputTokens || 0)), "hint": root.money(hermesOverview.today.costUsd) },
                                                { "label": "ACTIVE WORK", "value": String(hermesOverview.activeJobs + hermesOverview.activeTeams + hermesOverview.activeProposals), "hint": "OPEN WORK TAB" }
                                            ]
                                            Rectangle {
                                                id: hermesMetric
                                                required property var modelData
                                                width: (hermesOverview.width - Theme.cellW * 2) / 3
                                                height: Theme.cellH * 3.2
                                                radius: Theme.radius
                                                color: "transparent"
                                                border.width: 0
                                                Column {
                                                    anchors.centerIn: parent
                                                    spacing: 0
                                                    Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesMetric.modelData.label; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                                                    Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesMetric.modelData.value; color: Theme.fg; font.pixelSize: Theme.fontTitle; font.bold: true }
                                                    Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesMetric.modelData.hint; color: Theme.fgDim; font.pixelSize: Theme.fontCaption }
                                                }
                                            }
                                        }
                                    }

                                }
                            }

                            Row {
                                visible: root.page === 2
                                width: parent.width
                                spacing: Theme.cellW
                                Repeater {
                                    model: [
                                        { "id": "codex", "label": "CODEX", "hint": "native" },
                                        { "id": "claude", "label": "CLAUDE", "hint": "native" },
                                        { "id": "gemini", "label": "GEMINI", "hint": "API bridge" }
                                    ]
                                    InteractiveSurface {
                                        id: hermesProviderButton
                                        required property var modelData
                                        readonly property var providerState: (Agents.hermes.providers || {})[modelData.id] || ({ "ready": false })
                                        enabled: providerState.ready
                                        accessibleRole: Accessible.RadioButton
                                        accessibleName: modelData.label
                                        accessibleDescription: (modelData.id === Agents.hermesProvider ? "Selected. " : "")
                                            + (providerState.ready ? "Use " + modelData.label + " for Hermes" : modelData.label + " is not ready")
                                        accessibleSelected: modelData.id === Agents.hermesProvider
                                        width: (body.width - Theme.cellW * 2) / 3
                                        height: Theme.cellH * 2.6
                                        radius: Theme.radius
                                        color: modelData.id === Agents.hermesProvider ? Theme.selectedSurface(Theme.accent) : (hermesProviderHover.hovered || visualFocus ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: modelData.id === Agents.hermesProvider || visualFocus ? Theme.focusBorder : Theme.panelBorder
                                        onTriggered: Agents.setHermesProvider(modelData.id)
                                        onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(hermesProviderButton)
                                        Column {
                                            anchors.centerIn: parent
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesProviderButton.modelData.label; color: hermesProviderButton.providerState.ready ? Theme.fg : Theme.muted }
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesProviderButton.providerState.ready ? hermesProviderButton.modelData.hint : "not ready"; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                                        }
                                        HoverHandler { id: hermesProviderHover; cursorShape: hermesProviderButton.providerState.ready ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        TapHandler { enabled: hermesProviderButton.providerState.ready; onTapped: { hermesProviderButton.forceActiveFocus(Qt.MouseFocusReason); hermesProviderButton.activate(); } }
                                    }
                                }
                            }

                            Row {
                                visible: root.page === 2
                                width: parent.width
                                spacing: Theme.cellW
                                Repeater {
                                    model: [
                                        { "id": "restricted", "label": "RESTRICTED", "hint": "workspace files", "description": "Workspace files only" },
                                        { "id": "research", "label": "RESEARCH", "hint": "+ read-only web", "description": "Workspace files and read-only web access" },
                                        { "id": "workspace", "label": "WORKSPACE", "hint": "pilot + terminal", "description": "Workspace access with pilot and terminal tools" },
                                        { "id": "trusted", "label": "TRUSTED", "hint": "no approvals", "description": "Full project access; command approvals are disabled" }
                                    ]
                                    InteractiveSurface {
                                        id: hermesModeButton
                                        required property var modelData
                                        accessibleRole: Accessible.RadioButton
                                        accessibleName: modelData.label
                                        accessibleDescription: (modelData.id === Agents.hermesMode ? "Selected. " : "")
                                            + "Use Hermes " + modelData.label.toLowerCase() + " mode. " + modelData.description
                                        accessibleSelected: modelData.id === Agents.hermesMode
                                        width: (body.width - Theme.cellW * 3) / 4
                                        height: Theme.cellH * 2.6
                                        radius: Theme.radius
                                        color: modelData.id === Agents.hermesMode ? Theme.selectedSurface(Theme.accent) : (hermesModeHover.hovered || visualFocus ? Theme.hover : "transparent")
                                        border.width: Theme.borderWidth
                                        border.color: modelData.id === Agents.hermesMode || visualFocus ? Theme.focusBorder : Theme.panelBorder
                                        onTriggered: Agents.setHermesMode(modelData.id)
                                        onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(hermesModeButton)
                                        Column {
                                            anchors.centerIn: parent
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesModeButton.modelData.label; color: ["workspace", "trusted"].includes(hermesModeButton.modelData.id) ? Theme.yellow : Theme.fg }
                                            Line { anchors.horizontalCenter: parent.horizontalCenter; text: hermesModeButton.modelData.hint; color: Theme.muted; font.pixelSize: Theme.fontCaption }
                                        }
                                        HoverHandler { id: hermesModeHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: { hermesModeButton.forceActiveFocus(Qt.MouseFocusReason); hermesModeButton.activate(); } }
                                    }
                                }
                            }

                            Line { visible: root.page === 2; text: Agents.hermesMode === "trusted" ? "Trusted is fully autonomous in the selected Git project · commands do not ask for approval" : (Agents.hermesProvider === "gemini" ? "Gemini: Restricted/Research use plan mode · Workspace accepts edits in its sandbox" : "Native Hermes lane · credentials stay in the provider-owned store"); color: Agents.hermesMode === "trusted" ? Theme.red : Theme.muted }

                            Column {
                                width: parent.width
                                spacing: Theme.cellH * 0.2
                                visible: root.page === 0 && Agents.hermesProvider !== "gemini" && (Agents.hermes.sessions || []).length > 0
                                Line { text: "RECENT HERMES SESSIONS"; color: Theme.fgDim }
                                Repeater {
                                    model: (Agents.hermes.sessions || []).slice(0, 2)
                                    InteractiveSurface {
                                        id: hermesSession
                                        required property var modelData
                                        accessibleName: modelData.title || modelData.id
                                        accessibleDescription: "Resume Hermes session " + modelData.id
                                        width: body.width
                                        height: Theme.cellH * 2
                                        radius: Theme.radius
                                        color: hermesSessionHover.hovered || visualFocus ? Theme.hover : "transparent"
                                        border.width: Theme.borderWidth
                                        border.color: visualFocus ? Theme.focusBorder : Theme.panelBorder
                                        onTriggered: {
                                            Agents.resumeHermes(modelData.id);
                                            root.close();
                                        }
                                        onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(hermesSession)
                                        Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.5; text: String(hermesSession.modelData.title || hermesSession.modelData.id); color: Theme.fg; elide: Text.ElideRight }
                                        Line { anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; text: root.sessionTime(hermesSession.modelData.lastActive); color: Theme.fgDim }
                                        Line { anchors.right: parent.right; anchors.rightMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: root.compactTokens(hermesSession.modelData.inputTokens + hermesSession.modelData.outputTokens) + " TOK · RESUME"; color: Theme.accent }
                                        HoverHandler { id: hermesSessionHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: { hermesSession.forceActiveFocus(Qt.MouseFocusReason); hermesSession.activate(); } }
                                    }
                                }
                            }
                        }


                    }
                }

                Line {
                    width: parent.width
                    text: Agents.message !== "" ? Agents.message : "Esc closes · 1–3 switch views · F5 refreshes"
                    color: Agents.message !== "" ? Theme.yellow : Theme.muted
                    elide: Text.ElideRight
                }
            }
        }
    }
}
