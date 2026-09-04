pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Effects

Item {
    id: root
    required property bool primary
    required property bool previewMode
    required property string username
    required property string wallpaper
    required property color background
    required property color foreground
    required property color muted
    required property color accent
    required property color danger
    required property string fontFamily
    required property real dimOpacity
    required property string hourFormat
    required property bool reducedMotion
    required property bool showSecondsRing
    required property bool authenticating
    required property string statusMessage
    required property bool statusError
    required property int resetSerial
    property var currentTime: new Date()
    readonly property real unit: Math.max(0.62, Math.min(1.5, Math.min(width / 1920, height / 1080)))
    readonly property bool compact: width / Math.max(1, height) < 1.35
    signal submitted(string secret)
    signal resetRequested()
    signal quitPreview()
    function fileUrl(path) { return path ? "file://" + String(path).split("/").map(encodeURIComponent).join("/") : ""; }
    onResetSerialChanged: { passwordInput.text = ""; if (primary) passwordInput.forceActiveFocus(); }
    Component.onCompleted: if (primary) Qt.callLater(() => passwordInput.forceActiveFocus())
    // The outer seconds ring is deliberately smooth. When it is disabled,
    // the remaining minute ring does not justify rebuilding Date bindings at
    // ~30 Hz; a one-second cadence still keeps its fractional position exact.
    Timer { interval: root.showSecondsRing && !root.reducedMotion ? 33 : 1000; repeat: true; running: root.visible; onTriggered: root.currentTime = new Date() }

    Rectangle {
        anchors.fill: parent; color: root.background
        Image { id: image; anchors.fill: parent; source: root.fileUrl(root.wallpaper); fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false }
        MultiEffect { anchors.fill: image; source: image; autoPaddingEnabled: false; blurEnabled: image.status === Image.Ready; blur: 0.72; blurMax: 72; saturation: -0.28; contrast: -0.06 }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, root.dimOpacity) }
        OrbitalClock {
            width: root.compact ? Math.min(parent.width * 1.2, parent.height * 0.84) : Math.min(parent.width * 0.62, parent.height * 1.3)
            height: width; x: root.compact ? (parent.width-width)/2 : -width*0.49; y: root.compact ? -height*0.2 : (parent.height-height)/2
            currentTime: root.currentTime; foreground: root.foreground; hourFormat: root.hourFormat
            showSecondsRing: root.showSecondsRing && !root.reducedMotion; fontFamily: root.fontFamily
        }
        Text {
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 48 * root.unit
            text: "NBSHELL  ·  SESSION LOCKED"; color: root.foreground; font.family: root.fontFamily
            font.pixelSize: 11 * root.unit; font.bold: true; font.letterSpacing: 3 * root.unit
        }
        Column {
            anchors.centerIn: parent; spacing: 8 * root.unit
            Text { width: 520*root.unit; text: Qt.formatDate(root.currentTime,"dd MMM yyyy").toUpperCase(); color: root.muted; font.family: root.fontFamily; font.pixelSize: 15*root.unit; font.letterSpacing: 4*root.unit; horizontalAlignment: Text.AlignHCenter }
            Text { width: 520*root.unit; text: Qt.formatDate(root.currentTime,"dddd").toUpperCase(); color: root.foreground; font.family: root.fontFamily; font.pixelSize: 22*root.unit; font.bold: true; font.letterSpacing: 8*root.unit; horizontalAlignment: Text.AlignHCenter }
        }
        Column {
            id: panel; visible: root.primary; width: Math.min(450*root.unit,parent.width*0.86)
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 58*root.unit; spacing: 9*root.unit
            transform: Translate { id: failureOffset }
            Text { width: parent.width; text: root.username.toUpperCase(); color: root.foreground; font.family: root.fontFamily; font.pixelSize: 19*root.unit; font.bold: true; font.letterSpacing: 7*root.unit; horizontalAlignment: Text.AlignRight }
            Rectangle {
                width: parent.width; height: 62*root.unit; radius: height/2; color: Qt.rgba(root.background.r,root.background.g,root.background.b,0.78)
                border.width: Math.max(1,1.5*root.unit); border.color: root.statusError ? root.danger : (passwordInput.activeFocus ? root.accent : Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,0.5))
                Rectangle {
                    anchors.left: parent.left; anchors.leftMargin: 18*root.unit; anchors.verticalCenter: parent.verticalCenter
                    width: 42*root.unit; height: width; radius: width/2; color: Qt.rgba(root.foreground.r,root.foreground.g,root.foreground.b,0.1)
                    Text { anchors.centerIn: parent; text: "󰌾"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 23*root.unit }
                    SequentialAnimation on opacity { running: root.authenticating && !root.reducedMotion; loops: Animation.Infinite; NumberAnimation { to: .45; duration: 520 } NumberAnimation { to: 1; duration: 520 } }
                }
                Controls.TextField {
                    id: passwordInput; anchors.fill: parent; anchors.leftMargin: 78*root.unit; anchors.rightMargin: 26*root.unit
                    Accessible.name: "Password"; Accessible.description: root.statusMessage; Accessible.passwordEdit: true
                    background: null; enabled: !root.authenticating; leftPadding: 0; rightPadding: 0; echoMode: TextInput.Password; passwordCharacter: "✦"; passwordMaskDelay: 0
                    color: root.foreground; selectionColor: root.accent; font.family: root.fontFamily; font.pixelSize: 16*root.unit; font.letterSpacing: 8*root.unit
                    horizontalAlignment: TextInput.AlignRight; verticalAlignment: TextInput.AlignVCenter
                    onAccepted: { const secret=text; text=""; if (secret.length && !root.previewMode) root.submitted(secret); }
                    Keys.onPressed: event => { if (event.key===Qt.Key_Escape) { passwordInput.text=""; root.previewMode ? root.quitPreview() : root.resetRequested(); event.accepted=true; } else if ((event.modifiers & Qt.ControlModifier) && event.key===Qt.Key_U) { passwordInput.text=""; event.accepted=true; } }
                }
                Text { anchors.fill: passwordInput; visible: !passwordInput.text.length; text: root.previewMode ? "LOCK PREVIEW · PAM DISABLED" : (root.authenticating ? "AUTHENTICATING" : "ENTER PASSWORD"); color: root.statusError ? root.danger : root.muted; font.family: root.fontFamily; font.pixelSize: 11*root.unit; font.letterSpacing: 3*root.unit; horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter }
            }
            Text { width: parent.width; text: root.statusMessage; color: root.statusError ? root.danger : root.muted; font.family: root.fontFamily; font.pixelSize: 9*root.unit; font.letterSpacing: 2.5*root.unit; horizontalAlignment: Text.AlignRight }
            Text { width: parent.width; text: "CTRL+U  CLEAR   ·   ESC  RESET"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 8*root.unit; font.letterSpacing: 2*root.unit; horizontalAlignment: Text.AlignRight }
        }
        Text { visible: !root.primary; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 46*root.unit; text: "UNLOCK CONTROLS ON PRIMARY DISPLAY"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 9*root.unit; font.letterSpacing: 2.5*root.unit }
    }
    onStatusErrorChanged: if (statusError) { failureOffset.x = 0; if (!reducedMotion) failureShake.restart(); }
    onReducedMotionChanged: if (reducedMotion) { failureShake.stop(); failureOffset.x = 0; }
    SequentialAnimation { id: failureShake; NumberAnimation { target: failureOffset; property:"x"; to:-10*root.unit; duration:45 } NumberAnimation { target: failureOffset; property:"x"; to:10*root.unit; duration:70 } NumberAnimation { target: failureOffset; property:"x"; to:-6*root.unit; duration:60 } NumberAnimation { target: failureOffset; property:"x"; to:0; duration:45 } }
}
