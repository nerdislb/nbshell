import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Floating code and quiet caption adapted from the pinned Omarchy wifiqr
// panel. The matrix remains black on white, including its four-module quiet
// zone. Never tint, interpolate or expose the network password as UI text.
PanelWindow {
    id: root
    property var qr: null
    property bool loading: false
    readonly property var rows: qr && qr.ok ? qr.rows : []
    readonly property int size: qr && qr.ok ? qr.size : 0
    readonly property int modul: Math.max(1, Math.min(Math.round(Theme.cellH * .8),
        Math.floor(Math.min(box.width, Math.max(1, box.height - Theme.cellH * 9)) / Math.max(1, size))))

    visible: Runtime.qrOpen
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:wifi-qr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function load() {
        if (proc.running) return;
        qr = null;
        loading = true;
        proc.command = ["bash", Qt.resolvedUrl("../scripts/wifi-qr.sh").toString().replace("file://", "")];
        proc.running = true;
    }
    function close() {
        proc.running = false;
        qr = null;
        Runtime.qrOpen = false;
    }
    onVisibleChanged: if (visible) { load(); Qt.callLater(() => keys.forceActiveFocus()); }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!Runtime.qrOpen) return;
                root.loading = false;
                try { root.qr = JSON.parse(text); }
                catch (e) { root.qr = {ok:false,grund:"Could not generate the Wi-Fi QR code"}; }
            }
        }
    }
    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bg, .90) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        MotionSurface {
            id: box
            anchors.centerIn: parent
            width: Math.min(Theme.cellW * 60, parent.width - Theme.panelPadding * 2)
            height: Math.min(Theme.cellH * 38, parent.height - Theme.panelPadding * 2)
            color: "transparent"
            border.width: 0
            MouseArea { anchors.fill: parent }
            Column {
                anchors.centerIn: parent
                width: parent.width
                spacing: Theme.spaceLg
                Line {
                    width: parent.width
                    text: root.qr?.ok ? String(root.qr.ssid) : "Wi-Fi"
                    font.pixelSize: Theme.fontCaption
                    color: Theme.fgDim
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: qrCard
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.size * root.modul
                    height: width
                    visible: root.size > 0
                    color: "white"
                    Column {
                        spacing: 0
                        Repeater {
                            model: root.rows
                            Row {
                                required property string modelData
                                id: qrRow
                                spacing: 0
                                Repeater {
                                    model: qrRow.modelData.length
                                    Rectangle {
                                        required property int index
                                        width: root.modul; height: root.modul
                                        color: qrRow.modelData.charAt(index) === "#" ? "black" : "white"
                                    }
                                }
                            }
                        }
                    }
                }
                Line {
                    width: parent.width
                    text: root.loading ? "Generating QR code…" : root.qr?.ok
                        ? (String(root.qr.note || "") || "Scan to connect")
                        : String(root.qr?.grund || "No Wi-Fi connection")
                    color: root.qr && !root.qr.ok ? Theme.readable(Theme.red, Theme.bg) : Theme.fgDim
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spaceMd
                    ControlButton { text: "Retry"; enabled: !root.loading; onTriggered: root.load() }
                    ControlButton { text: "Close"; onTriggered: root.close() }
                }
            }
        }
    }
}
