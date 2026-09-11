import QtQuick
import QtQuick.Controls as Controls
import qs.Common
import qs.Widgets

PanelSurface {
    id: root
    property var flow: null
    property bool submitted: false
    readonly property bool responding: flow !== null && !flow.isCompleted && flow.isResponseRequired && !submitted
    property alias responseField: response
    accentBorder: true
    implicitWidth: Theme.cellW * 58
    implicitHeight: body.implicitHeight + Theme.panelPadding * 2

    function resetInput() {
        response.clear();
        submitted = false;
    }
    function focusInput() {
        if (responding)
            response.forceActiveFocus();
        else
            cancel.forceActiveFocus();
    }
    function submit() {
        if (!responding)
            return;
        submitted = true;
        // No process, command line, IPC or log carries the response.
        flow.submit(response.text);
        response.clear();
    }
    function cancelRequest() {
        response.clear();
        if (flow && !flow.isCompleted)
            flow.cancelAuthenticationRequest();
    }
    onRespondingChanged: Qt.callLater(root.focusInput)
    onFlowChanged: {
        resetInput();
        Qt.callLater(root.focusInput);
    }
    onVisibleChanged: {
        if (!visible) resetInput();
        else Qt.callLater(root.focusInput);
    }
    Component.onDestruction: response.clear()
    Keys.onEscapePressed: event => { cancelRequest(); event.accepted = true; }

    Connections {
        target: root.flow
        function onIsResponseRequiredChanged() { root.resetInput(); Qt.callLater(root.focusInput); }
        function onInputPromptChanged() { root.resetInput(); Qt.callLater(root.focusInput); }
        function onResponseVisibleChanged() { root.resetInput(); }
        function onSelectedIdentityChanged() { root.resetInput(); Qt.callLater(root.focusInput); }
        function onAuthenticationFailed() { root.resetInput(); Qt.callLater(root.focusInput); }
        function onIsCompletedChanged() { root.resetInput(); }
    }

    Controls.ScrollView {
        anchors.fill: parent
        anchors.margins: Theme.panelPadding
        contentWidth: availableWidth
        clip: true
        Column {
            id: body
            width: parent.width
            spacing: Theme.spaceMd
            PanelHead {
                rowWidth: body.width
                icon: Icons.cp(0xF033E)
                title: "Authentication required"
                subtitle: "nbshell · system authorization"
            }
            Line {
                width: body.width
                text: root.flow ? root.flow.message : ""
                wrapMode: Text.Wrap
            }
            Line {
                width: body.width
                text: root.flow ? root.flow.actionId : ""
                color: Theme.fgDim
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.Wrap
            }
            Column {
                width: body.width
                spacing: Theme.spaceXs
                Repeater {
                    id: identities
                    model: root.flow ? root.flow.identities : []
                    ControlButton {
                        required property var modelData
                        required property int index
                        KeyNavigation.tab: index + 1 < identities.count ? identities.itemAt(index + 1) : (root.responding ? response : cancel)
                        KeyNavigation.backtab: index > 0 ? identities.itemAt(index - 1) : cancel
                        width: body.width
                        text: String(modelData.displayName || modelData.string || modelData.id)
                        selected: root.flow !== null && root.flow.selectedIdentity === modelData
                        enabled: root.flow !== null && !root.flow.isCompleted
                        onTriggered: {
                            root.resetInput();
                            if (root.flow && !root.flow.isCompleted)
                                root.flow.selectedIdentity = modelData;
                        }
                    }
                }
            }
            Line {
                width: body.width
                visible: text !== ""
                text: root.flow ? (root.flow.supplementaryMessage || (root.flow.failed ? "Authentication failed. Please try again." : "")) : ""
                color: root.flow && (root.flow.supplementaryMessage ? root.flow.supplementaryIsError : root.flow.failed) ? Theme.red : Theme.fgDim
                wrapMode: Text.Wrap
                Accessible.role: Accessible.AlertMessage
            }
            Line {
                width: body.width
                text: root.responding ? (root.flow.inputPrompt || "Response") : "Waiting for authentication…"
                wrapMode: Text.Wrap
            }
            TextField {
                id: response
                width: body.width
                visible: root.flow !== null && root.flow.isResponseRequired
                enabled: root.responding
                password: !(root.flow && root.flow.responseVisible)
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                accessibleName: root.flow ? root.flow.inputPrompt : "Authentication response"
                onAccepted: root.submit()
                KeyNavigation.tab: authenticate.enabled ? authenticate : cancel
                KeyNavigation.backtab: identities.count > 1 ? identities.itemAt(identities.count - 1) : cancel
            }
            Row {
                width: body.width
                spacing: Theme.spaceMd
                ActionButton {
                    id: cancel
                    text: "Cancel"
                    width: (body.width - Theme.spaceMd) / 2
                    onTriggered: root.cancelRequest()
                    KeyNavigation.tab: identities.count > 1 ? identities.itemAt(0) : (root.responding ? response : cancel)
                    KeyNavigation.backtab: authenticate.enabled ? authenticate : cancel
                }
                ActionButton {
                    id: authenticate
                    text: "Authenticate"
                    tone: "primary"
                    enabled: root.responding
                    width: (body.width - Theme.spaceMd) / 2
                    onTriggered: root.submit()
                    KeyNavigation.tab: cancel
                    KeyNavigation.backtab: response
                }
            }
        }
    }
}
