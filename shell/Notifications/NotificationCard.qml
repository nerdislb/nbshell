import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

Rectangle {
    id: root

    required property var entry
    property bool selected: false
    property bool detailed: true
    property bool showActions: true

    signal opened()
    signal removed()

    readonly property bool urgent: entry.urgency === NotificationUrgency.Critical || entry.urgency === 2
    readonly property string iconName: Notify.sourceIcon(entry)
    readonly property string iconPath: iconName !== "" ? Quickshell.iconPath(iconName, true) : ""
    readonly property var liveActions: entry.notification?.actions ?? []

    implicitHeight: content.implicitHeight + Theme.cellH * 0.7
    radius: Theme.radius
    color: selected || hover.hovered ? Theme.hover : Theme.bgLight
    border.width: Theme.borderWidth
    border.color: urgent ? Theme.red : (selected ? Theme.accent : Theme.muted)

    Row {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Math.round(Theme.cellW * 0.75)
        spacing: Theme.cellW

        Item {
            width: Theme.cellH * 2
            height: Theme.cellH * 2
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.alpha(root.urgent ? Theme.red : Theme.accent, 0.13)
                border.width: Theme.borderWidth
                border.color: root.urgent ? Theme.red : Theme.accent
            }

            Image {
                anchors.centerIn: parent
                width: parent.width * 0.68
                height: width
                sourceSize.width: Math.ceil(Theme.cellH * 1.36)
                sourceSize.height: Math.ceil(Theme.cellH * 1.36)
                source: root.iconPath
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status !== Image.Error && source !== ""
            }

            Line {
                anchors.centerIn: parent
                visible: root.iconPath === ""
                text: Notify.sourceName(root.entry).slice(0, 1).toUpperCase()
                color: root.urgent ? Theme.red : Theme.accent
                font.bold: true
            }
        }

        Column {
            width: parent.width - Theme.cellH * 2 - parent.spacing
            spacing: Math.round(Theme.cellH * 0.12)

            Row {
                width: parent.width

                Line {
                    width: parent.width - age.width
                    text: Notify.sourceName(root.entry).toUpperCase()
                        + ((root.entry.repeat ?? 1) > 1 ? "  ×" + root.entry.repeat : "")
                    color: root.urgent ? Theme.red : Theme.accent
                    font.bold: true
                    elide: Text.ElideRight
                }

                Line {
                    id: age
                    text: Notify.ago(root.entry.time)
                    color: Theme.fgDim
                }
            }

            Line {
                width: parent.width
                text: root.entry.summary || ""
                color: Theme.fgBright
                font.pixelSize: Theme.fontSize + 1
                wrapMode: Text.WordWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Line {
                width: parent.width
                visible: root.detailed && text !== ""
                text: Notify.plain(root.entry.body)
                color: Theme.fgDim
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Flow {
                width: parent.width
                spacing: Math.round(Theme.cellW * 0.7)
                visible: root.showActions

                ActionButton {
                    text: "Open"
                    tone: "primary"
                    compact: true
                    onTriggered: root.opened()
                }

                Repeater {
                    model: root.liveActions.filter(a => a.identifier !== "default")

                    ActionButton {
                        required property var modelData
                        text: modelData.text || "Aktion"
                        compact: true
                        onTriggered: Notify.invoke(root.entry.key, modelData)
                    }
                }

                ActionButton {
                    text: "Dismiss"
                    tone: "danger"
                    compact: true
                    onTriggered: root.removed()
                }
            }
        }
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? root.removed() : root.opened()
    }
}
