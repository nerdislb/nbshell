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
    property bool unread: false

    signal opened()
    signal removed()

    readonly property bool urgent: entry.urgency === NotificationUrgency.Critical || entry.urgency === 2
    readonly property string iconName: Notify.sourceIcon(entry)
    readonly property string iconPath: resolveIcon(iconName)
    readonly property bool iconAvailable: iconPath !== "" && appIcon.status !== Image.Error
    readonly property string fallbackIcon: Notify.sourceGlyph(entry)
    readonly property var liveActions: entry.notification?.actions ?? []

    function resolveIcon(value) {
        const raw = String(value || "");
        if (raw === "")
            return "";
        if (raw.startsWith("file://") || raw.startsWith("image://"))
            return raw;
        if (raw.startsWith("/"))
            return "file://" + raw;
        // Notifications may contain remote URLs. Loading those here would
        // make merely opening the center contact a third-party server.
        if (raw.indexOf("://") >= 0)
            return "";
        return Quickshell.iconPath(raw, true);
    }

    implicitHeight: content.implicitHeight + Theme.cellH * 0.9
    radius: Math.max(Theme.radius, Theme.cellH * 0.58)
    color: selected ? Theme.selectedSurface(urgent ? Theme.red : Theme.accent)
        : Theme.alpha(Theme.fg, hover.hovered ? 0.11 : 0.06)
    border.width: selected ? Theme.borderWidth : 0
    border.color: selected ? Theme.focusBorder : "transparent"

    Behavior on color { ColorAnimation { duration: Theme.motionEffectsFast } }

    Rectangle {
        visible: root.urgent
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Theme.cellH * 0.35
        width: Math.max(3, Theme.borderWidth * 2)
        radius: width / 2
        color: Theme.red
    }

    Rectangle {
        visible: root.unread && !root.urgent
        anchors.left: parent.left
        anchors.leftMargin: Theme.cellW * 0.45
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(4, Theme.borderWidth * 3)
        height: width
        radius: width / 2
        color: Theme.accent
    }

    Row {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Math.round(Theme.cellW * 0.75)
        spacing: Theme.cellW

        Item {
            width: Math.round(Theme.cellH * 2.15)
            height: width
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: Math.max(Theme.radius, Theme.cellH * 0.45)
                color: Theme.alpha(root.urgent ? Theme.red : Theme.fg, 0.11)
                visible: !root.iconAvailable
            }

            Image {
                id: appIcon
                anchors.centerIn: parent
                width: parent.width * 0.88
                height: width
                sourceSize.width: Math.ceil(parent.width * 1.5)
                sourceSize.height: Math.ceil(parent.width * 1.5)
                source: root.iconPath
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                mipmap: true
                visible: root.iconAvailable
            }

            Line {
                anchors.centerIn: parent
                visible: !root.iconAvailable
                text: root.fallbackIcon !== ""
                    ? root.fallbackIcon
                    : Notify.sourceName(root.entry).slice(0, 1).toUpperCase()
                color: root.selected ? Theme.selectedForeground(root.urgent ? Theme.red : Theme.accent)
                    : Theme.fgDim
                font.pixelSize: root.fallbackIcon !== "" ? Theme.fontTitle : Theme.fontSubtitle
                font.bold: true
            }
        }

        Column {
            width: parent.width - Math.round(Theme.cellH * 2.15) - parent.spacing
            spacing: Math.round(Theme.cellH * 0.12)

            Row {
                width: parent.width

                Line {
                    width: parent.width - age.width
                    text: Notify.sourceName(root.entry).toUpperCase()
                        + ((root.entry.repeat ?? 1) > 1 ? "  ×" + root.entry.repeat : "")
                    color: root.selected ? Theme.selectedForeground(root.urgent ? Theme.red : Theme.accent)
                        : Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                    font.bold: true
                    elide: Text.ElideRight
                }

                Line {
                    id: age
                    visible: !hover.hovered || root.showActions
                    text: Notify.ago(root.entry.time)
                    color: Theme.fgDim
                }
            }

            Line {
                width: parent.width
                text: root.entry.summary || ""
                color: Theme.fgBright
                font.pixelSize: Theme.fontSubtitle
                wrapMode: Text.WordWrap
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Line {
                width: parent.width
                visible: root.detailed && text !== ""
                text: Notify.plain(root.entry.body)
                color: Theme.fgDim
                font.pixelSize: Theme.fontBody
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
                        text: modelData.text || "Action"
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

    Rectangle {
        visible: hover.hovered && !root.showActions
        anchors.right: parent.right
        anchors.rightMargin: Theme.cellW * 0.7
        anchors.top: parent.top
        anchors.topMargin: Theme.cellH * 0.45
        width: Theme.cellH * 1.05
        height: width
        radius: width / 2
        color: dismissHover.hovered ? Theme.alpha(Theme.fg, 0.24) : Theme.alpha(Theme.fg, 0.13)
        z: 3

        Line {
            anchors.centerIn: parent
            text: "×"
            color: Theme.fg
            font.pixelSize: Theme.fontBody
        }

        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.removeRequested() }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? root.removed() : root.opened()
    }
}
