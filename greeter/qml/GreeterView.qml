// Presentation adapted from dumidulkdev/omarchy-orbital-lock (MIT), commit 6639304.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
    id: root

    required property bool primary
    required property bool previewMode
    required property string username
    required property string wallpaper
    required property color background
    required property color foreground
    required property color bright
    required property color muted
    required property color accent
    required property color danger
    required property string fontFamily
    required property int fontSize
    required property real dimOpacity
    required property string hourFormat
    required property bool reducedMotion
    required property bool showSecondsRing
    required property bool showPowerActions
    required property bool authenticating
    required property bool externalAuthActive
    required property bool launching
    required property bool responseRequired
    required property bool echoResponse
    required property string promptMessage
    required property string statusMessage
    required property bool statusError
    required property int failedAttempts
    required property string sessionName
    required property int sessionCount
    required property int passwordResetSerial
    required property int promptSerial

    property var currentTime: new Date()
    property string pendingPowerAction: ""

    readonly property bool compact: width / Math.max(1, height) < 1.35
    readonly property real uiScale: Math.max(0.62, Math.min(1.5, Math.min(width / 1920, height / 1080)))

    signal submitResponse(string response)
    signal startExternalAuth()
    signal cancelAuthentication()
    signal cycleSession(int step)
    signal powerAction(string action)
    signal quitPreview()

    function alpha(colorValue, opacity) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, opacity);
    }

    function fileUrl(path) {
        if (!path)
            return "";
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    function focusPrimaryAction() {
        if (!primary)
            return;
        if (passwordInput.enabled)
            passwordInput.forceActiveFocus(Qt.TabFocusReason);
        else if (passwordModeAction.visible && passwordModeAction.interactive)
            passwordModeAction.forceActiveFocus(Qt.TabFocusReason);
        else if (sessionSwitcher.visible && sessionSwitcher.interactive)
            sessionSwitcher.forceActiveFocus(Qt.TabFocusReason);
        else
            root.forceActiveFocus(Qt.OtherFocusReason);
    }

    function requestPower(action) {
        if (previewMode || launching)
            return;
        if (pendingPowerAction === action) {
            pendingPowerAction = "";
            powerConfirmationTimer.stop();
            powerAction(action);
            return;
        }
        pendingPowerAction = action;
        powerConfirmationTimer.restart();
    }

    onPasswordResetSerialChanged: passwordInput.text = ""
    onPromptSerialChanged: Qt.callLater(focusPrimaryAction)
    Component.onCompleted: Qt.callLater(focusPrimaryAction)
    focus: primary
    Keys.onEscapePressed: event => {
        if (root.previewMode)
            root.quitPreview();
        else
            root.cancelAuthentication();
        event.accepted = true;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_F2 && !event.isAutoRepeat) {
            root.cycleSession(1);
            event.accepted = true;
        }
    }

    Timer {
        interval: root.showSecondsRing && !root.reducedMotion ? 33 : 1000
        repeat: true
        running: root.visible
        onTriggered: root.currentTime = new Date()
    }

    Timer {
        id: powerConfirmationTimer
        interval: 5000
        repeat: false
        onTriggered: root.pendingPowerAction = ""
    }

    Rectangle {
        anchors.fill: parent
        color: root.background

        Image {
            id: wallpaperImage
            anchors.fill: parent
            source: root.wallpaper ? root.fileUrl(root.wallpaper) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: width
            sourceSize.height: height
        }

        MultiEffect {
            anchors.fill: wallpaperImage
            source: wallpaperImage
            autoPaddingEnabled: false
            blurEnabled: wallpaperImage.status === Image.Ready
            blur: 0.72
            blurMax: 72
            blurMultiplier: 1.05
            saturation: -0.28
            contrast: -0.06
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, root.dimOpacity)
        }

        OrbitalClock {
            z: 2
            width: root.compact ? Math.min(parent.width * 1.2, parent.height * 0.84) : Math.min(parent.width * 0.62, parent.height * 1.3)
            height: width
            x: root.compact ? (parent.width - width) / 2 : -width * 0.49
            y: root.compact ? -height * 0.2 : (parent.height - height) / 2
            currentTime: root.currentTime
            foreground: root.foreground
            showSecondsRing: root.showSecondsRing && !root.reducedMotion
            authenticating: root.authenticating || root.launching
            hourFormat: root.hourFormat
            fontFamily: root.fontFamily
        }

        Row {
            z: 5
            anchors.right: parent.right
            anchors.rightMargin: 54 * root.uiScale
            anchors.top: parent.top
            anchors.topMargin: 42 * root.uiScale
            spacing: 22 * root.uiScale

            Text {
                text: "NBSHELL"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 11 * root.uiScale
                font.weight: Font.Bold
                font.letterSpacing: 3 * root.uiScale
            }

            ActionLabel {
                id: sessionSwitcher
                label: root.sessionName.toUpperCase()
                accessibleDescription: root.sessionCount > 1 ? "Select the next session" : "Selected session"
                active: true
                interactive: root.primary && root.sessionCount > 1 && !root.launching
                onTriggered: root.cycleSession(1)
            }

            ActionLabel {
                id: rebootAction
                visible: root.showPowerActions
                label: root.pendingPowerAction === "reboot" ? "CONFIRM REBOOT" : "REBOOT"
                accessibleDescription: root.pendingPowerAction === "reboot" ? "Press again to restart the computer" : "Request computer restart"
                active: root.pendingPowerAction === "reboot"
                interactive: root.primary && !root.previewMode && !root.launching
                onTriggered: root.requestPower("reboot")
            }

            ActionLabel {
                id: shutdownAction
                visible: root.showPowerActions
                label: root.pendingPowerAction === "poweroff" ? "CONFIRM SHUTDOWN" : "SHUTDOWN"
                accessibleDescription: root.pendingPowerAction === "poweroff" ? "Press again to shut down the computer" : "Request computer shutdown"
                active: root.pendingPowerAction === "poweroff"
                interactive: root.primary && !root.previewMode && !root.launching
                onTriggered: root.requestPower("poweroff")
            }
        }

        Column {
            z: 3
            width: root.compact ? parent.width * 0.86 : Math.min(560 * root.uiScale, parent.width * 0.46)
            x: (parent.width - width) / 2
            y: root.compact ? parent.height * 0.43 : (parent.height - implicitHeight) / 2
            spacing: 8 * root.uiScale

            Text {
                width: parent.width
                text: Qt.formatDate(root.currentTime, "dd MMM yyyy").toUpperCase()
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 15 * root.uiScale
                font.letterSpacing: 4 * root.uiScale
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: Qt.formatDate(root.currentTime, "dddd").toUpperCase()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 22 * root.uiScale
                font.weight: Font.Bold
                font.letterSpacing: 8 * root.uiScale
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Column {
            id: identityPanel
            z: 4
            visible: root.primary
            width: Math.min(450 * root.uiScale, parent.width * 0.86)
            x: root.compact ? (parent.width - width) / 2 : parent.width - width - 66 * root.uiScale
            y: parent.height - implicitHeight - 58 * root.uiScale
            spacing: 9 * root.uiScale
            transform: Translate { id: failureOffset }

            Text {
                width: parent.width
                text: root.username.toUpperCase()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 19 * root.uiScale
                font.weight: Font.Bold
                font.letterSpacing: 7 * root.uiScale
                horizontalAlignment: Text.AlignRight
            }

            Row {
                anchors.right: parent.right
                spacing: 14 * root.uiScale

                ActionLabel {
                    id: passwordModeAction
                    label: root.responseRequired ? "ENTER PASSWORD" : (root.authenticating ? "WAITING FOR PASSWORD" : "START PASSWORD LOGIN")
                    accessibleDescription: "Start password authentication"
                    active: root.responseRequired
                    interactive: !root.previewMode && !root.launching && !root.authenticating
                    onTriggered: root.startExternalAuth()
                }
                ActionLabel {
                    id: cancelAuthAction
                    label: "CANCEL"
                    accessibleDescription: "Cancel authentication"
                    visible: root.authenticating
                    interactive: !root.launching
                    onTriggered: root.cancelAuthentication()
                }
            }

            Rectangle {
                id: passwordField
                width: parent.width
                height: 62 * root.uiScale
                radius: height / 2
                color: root.alpha(root.background, 0.78)
                border.width: Math.max(1, 1.5 * root.uiScale)
                border.color: root.statusError ? root.danger : (passwordInput.activeFocus ? root.accent : root.alpha(root.foreground, root.responseRequired ? 0.55 : 0.25))

                Rectangle {
                    id: fingerprintHalo
                    anchors.left: parent.left
                    anchors.leftMargin: 18 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42 * root.uiScale
                    height: width
                    radius: width / 2
                    color: root.alpha(root.foreground, root.responseRequired ? 0.10 : 0.035)
                    border.width: Math.max(1, root.uiScale)
                    border.color: root.alpha(root.foreground, root.responseRequired ? 0.52 : 0.16)
                    scale: root.responseRequired ? 1.08 : 1
                    Behavior on scale { enabled: !root.reducedMotion; NumberAnimation { duration: 550; easing.type: Easing.InOutSine } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰌾"
                        color: root.responseRequired ? root.foreground : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: 23 * root.uiScale
                    }

                    SequentialAnimation on opacity {
                        running: root.authenticating && !root.responseRequired && !root.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.45; duration: 520; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.45; to: 1; duration: 520; easing.type: Easing.InOutSine }
                    }
                }

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    anchors.leftMargin: 78 * root.uiScale
                    anchors.rightMargin: 26 * root.uiScale
                    horizontalAlignment: TextInput.AlignRight
                    verticalAlignment: TextInput.AlignVCenter
                    activeFocusOnPress: true
                    activeFocusOnTab: enabled
                    enabled: root.primary && !root.launching && root.responseRequired
                    Accessible.role: Accessible.EditableText
                    Accessible.name: root.echoResponse ? "Authentication response" : "Password"
                    Accessible.description: root.promptMessage || root.statusMessage
                    Accessible.passwordEdit: !root.echoResponse
                    Accessible.focusable: enabled
                    Accessible.focused: activeFocus
                    echoMode: root.echoResponse ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "✦"
                    passwordMaskDelay: 0
                    color: root.foreground
                    selectionColor: root.accent
                    selectedTextColor: root.background
                    font.family: root.fontFamily
                    font.pixelSize: 16 * root.uiScale
                    font.letterSpacing: 8 * root.uiScale

                    onAccepted: {
                        const response = text;
                        text = "";
                        if (response.length > 0)
                            root.submitResponse(response);
                    }

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            if (root.previewMode)
                                root.quitPreview();
                            else
                                root.cancelAuthentication();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_F2 && !event.isAutoRepeat) {
                            root.cycleSession(1);
                            event.accepted = true;
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) {
                            passwordInput.text = "";
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.fill: passwordInput
                    visible: passwordInput.text.length === 0
                    text: root.previewMode ? "GREETER PREVIEW" : (root.launching ? "STARTING SESSION" : (root.responseRequired ? (root.promptMessage || (root.echoResponse ? "ENTER RESPONSE" : "ENTER PASSWORD")) : "WAITING FOR PASSWORD PROMPT"))
                    color: root.statusError ? root.danger : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 11 * root.uiScale
                    font.letterSpacing: 3 * root.uiScale
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    Accessible.ignored: true
                }
            }

            Text {
                width: parent.width
                text: root.statusMessage + (root.failedAttempts > 0 && root.statusError ? "  ·  ATTEMPT " + root.failedAttempts : "")
                color: root.statusError ? root.danger : root.muted
                font.family: root.fontFamily
                font.pixelSize: 9 * root.uiScale
                font.letterSpacing: 2.5 * root.uiScale
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Text {
                width: parent.width
                text: "F2  SESSION   ·   ESC  " + (root.previewMode ? "CLOSE PREVIEW" : "CANCEL")
                color: root.alpha(root.muted, 0.76)
                font.family: root.fontFamily
                font.pixelSize: 8 * root.uiScale
                font.letterSpacing: 2 * root.uiScale
                horizontalAlignment: Text.AlignRight
            }
        }

        Text {
            visible: !root.primary
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 46 * root.uiScale
            text: "LOGIN CONTROLS ON PRIMARY DISPLAY"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 9 * root.uiScale
            font.letterSpacing: 2.5 * root.uiScale
        }
    }

    onStatusErrorChanged: if (statusError) { failureOffset.x = 0; if (!reducedMotion) failureShake.restart(); }
    onReducedMotionChanged: if (reducedMotion) { failureShake.stop(); failureOffset.x = 0; }

    SequentialAnimation {
        id: failureShake
        NumberAnimation { target: failureOffset; property: "x"; from: 0; to: -10 * root.uiScale; duration: 45 }
        NumberAnimation { target: failureOffset; property: "x"; to: 10 * root.uiScale; duration: 70 }
        NumberAnimation { target: failureOffset; property: "x"; to: -6 * root.uiScale; duration: 60 }
        NumberAnimation { target: failureOffset; property: "x"; to: 0; duration: 45 }
    }

    component ActionLabel: Item {
        id: actionRoot
        property string label: ""
        property string accessibleDescription: ""
        property bool active: false
        property bool interactive: true
        signal triggered()
        function activate() {
            if (interactive && visible && enabled)
                triggered();
        }
        width: actionText.implicitWidth
        height: actionText.implicitHeight
        opacity: interactive ? 1 : 0.45
        activeFocusOnTab: interactive && visible && enabled
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.description: accessibleDescription
        Accessible.focusable: activeFocusOnTab
        Accessible.focused: activeFocus
        Accessible.onPressAction: actionRoot.activate()
        Keys.onReturnPressed: event => {
            event.accepted = true;
            if (!event.isAutoRepeat) actionRoot.activate();
        }
        Keys.onEnterPressed: event => {
            event.accepted = true;
            if (!event.isAutoRepeat) actionRoot.activate();
        }
        Keys.onSpacePressed: event => {
            event.accepted = true;
            if (!event.isAutoRepeat) actionRoot.activate();
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4 * root.uiScale
            color: "transparent"
            border.width: actionRoot.activeFocus ? Math.max(1, root.uiScale) : 0
            border.color: root.accent
            radius: 2 * root.uiScale
        }

        Text {
            id: actionText
            text: actionRoot.label
            color: actionRoot.active || actionRoot.activeFocus || actionMouse.containsMouse ? root.foreground : root.muted
            font.family: root.fontFamily
            font.pixelSize: 10 * root.uiScale
            font.weight: actionRoot.active ? Font.Bold : Font.Normal
            font.letterSpacing: 2.5 * root.uiScale
            Behavior on color { enabled: !root.reducedMotion; ColorAnimation { duration: 140 } }
        }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: actionRoot.interactive
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                actionRoot.forceActiveFocus(Qt.MouseFocusReason);
                actionRoot.activate();
            }
        }
    }
}
