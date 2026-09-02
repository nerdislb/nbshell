import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root

    required property real rowWidth
    property real sectionSpacing: Theme.cellH * 0.2
    property bool active: false

    readonly property bool available: Nearby.enabled

    width: root.rowWidth
    spacing: root.sectionSpacing
    visible: root.available

    onActiveChanged: Nearby.wanted = root.active
    Component.onDestruction: {
        if (root.active)
            Nearby.wanted = false;
    }

    Rule {
        rowWidth: root.rowWidth
        label: "NEARBY · LOCALSEND"
    }

    Line {
        visible: root.available && Nearby.devices.length === 0
        width: root.rowWidth
        text: Nearby.scanning ? "  scanning …" : "  no devices — LocalSend must be open on the other device"
        color: Theme.muted
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.available ? Nearby.devices : []

        Rectangle {
            id: deviceRow
            required property var modelData

            width: root.rowWidth
            height: deviceBody.implicitHeight + Theme.cellH
            radius: Theme.radius
            color: Theme.alpha(Theme.fg, 0.05)
            border.width: Theme.borderWidth
            border.color: Theme.alpha(Theme.fg, 0.12)

            Column {
                id: deviceBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.cellW
                anchors.rightMargin: Theme.cellW
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.cellH * 0.2

                Item {
                    width: parent.width
                    height: deviceAlias.implicitHeight

                    Line {
                        id: deviceAlias
                        anchors.left: parent.left
                        text: deviceRow.modelData.alias
                        color: Theme.fg
                    }
                    Line {
                        anchors.right: parent.right
                        text: deviceRow.modelData.model + "  " + deviceRow.modelData.ip
                        color: Theme.muted
                    }
                }

                Row {
                    spacing: Theme.cellW * 2

                    component NearbyAction: ActionButton {
                        compact: true
                    }

                    NearbyAction {
                        text: "Clipboard"
                        onTriggered: Nearby.sendText(deviceRow.modelData, Clipboard.entries.length > 0 ? Clipboard.entries[0] : "")
                    }

                    NearbyAction {
                        text: "Latest image"
                        onTriggered: Nearby.sendLastShot(deviceRow.modelData)
                    }
                }
            }
        }
    }

    Line {
        visible: root.available && Nearby.status !== ""
        width: root.rowWidth
        text: "  " + Nearby.status
        color: Nearby.status.indexOf("failed") === 0 ? Theme.red : Theme.green
        wrapMode: Text.WordWrap
    }

    Line {
        visible: root.available
        text: "  Files: nbshell nearby send <file>"
        color: Theme.muted
        font.pixelSize: Theme.fontSize - 1
    }
}
