import QtQuick
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import qs.Widgets

// Compact native toast used only by the passive top-right popup stack.
// Notification history keeps the richer NotificationCard representation.
PanelSurface {
    id: root

    required property var entry

    signal opened()
    signal removed()

    readonly property bool urgent: entry.urgency === NotificationUrgency.Critical
        || entry.urgency === 2

    function activate() {
        root.opened();
    }

    implicitWidth: Theme.cellW * 48
    implicitHeight: body.implicitHeight + Theme.spaceMd * 2
    raised: true
    accentBorder: true
    border.color: urgent ? Theme.red : Theme.focusBorder

    Accessible.role: Accessible.AlertMessage
    Accessible.name: entry.summary || Notify.sourceName(entry)
    Accessible.description: [Notify.sourceName(entry), Notify.plain(entry.body || ""),
        urgent ? "Urgent" : ""].filter(part => part !== "").join("; ")
    Accessible.onPressAction: root.activate()

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: Notify.setPopupHovered(root.entry.key, hovered)
    }

    Component.onDestruction: {
        if (hover.hovered)
            Notify.setPopupHovered(root.entry.key, false);
    }

    Column {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spaceMd
        spacing: Theme.spaceXs

        Line {
            width: parent.width
            text: (root.urgent ? "! " : "") + Notify.sourceName(root.entry).toUpperCase()
                + "  ·  " + Notify.ago(root.entry.time)
            color: root.urgent ? Theme.red : Theme.fgDim
            font.pixelSize: Theme.fontCaption
            font.bold: true
            elide: Text.ElideRight
        }

        Line {
            width: parent.width
            visible: text !== ""
            text: root.entry.summary || ""
            color: Theme.fgBright
            font.pixelSize: Theme.fontSubtitle
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Line {
            width: parent.width
            visible: text !== ""
            text: Notify.plain(root.entry.body || "")
            color: Theme.fg
            font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: function(eventPoint, button) {
            if (button === Qt.RightButton)
                root.removed();
            else
                root.activate();
        }
    }
}
