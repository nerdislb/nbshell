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
    property bool keyboardSelected: false
    property bool detailed: true
    property bool showActions: true
    property bool unread: false
    // Popup notifications sit directly on the wallpaper; history entries are
    // drawn as compact rows inside the notification-center panel.
    property bool standalone: false

    signal opened()
    signal removed()
    readonly property Item firstAction: openButton
    signal controlFocused(Item control)
    signal focusEntered()

    onActiveFocusChanged: if (activeFocus) focusEntered()

    readonly property bool urgent: entry.urgency === NotificationUrgency.Critical || entry.urgency === 2
    readonly property string iconName: Notify.sourceIcon(entry)
    readonly property string iconPath: resolveIcon(iconName)
    readonly property bool iconAvailable: iconPath !== "" && appIcon.status !== Image.Error
    readonly property string fallbackIcon: Notify.sourceGlyph(entry)
    readonly property var liveActions: entry.notification?.actions ?? []
    readonly property bool hovered: hover.hovered

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

    function activateFromKey(event) {
        if (!event.isAutoRepeat)
            root.opened();
        event.accepted = true;
    }

    implicitHeight: content.implicitHeight + Theme.toastPaddingY * 2
    radius: Theme.radius
    color: selected ? Theme.menuSelection : hovered ? Theme.networkHover : "transparent"
    border.width: activeFocus || keyboardSelected || urgent ? Theme.borderWidth : 0
    border.color: activeFocus || keyboardSelected ? Theme.focusBorder : Theme.red
    activeFocusOnTab: enabled && !showActions

    Accessible.role: showActions ? Accessible.ListItem : Accessible.AlertMessage
    Accessible.name: entry.summary || Notify.sourceName(entry)
    Accessible.description: [Notify.sourceName(entry), Notify.plain(entry.body || ""),
        urgent ? "Urgent" : "", unread ? "Unread" : ""].filter(part => part !== "").join("; ")
    Accessible.focusable: enabled && !showActions
    Accessible.focused: activeFocus
    Accessible.selected: selected
    Accessible.onPressAction: if (!showActions) root.opened()

    Keys.onReturnPressed: event => root.activateFromKey(event)
    Keys.onEnterPressed: event => root.activateFromKey(event)
    Keys.onSpacePressed: event => root.activateFromKey(event)
    Keys.onDeletePressed: event => {
        if (!event.isAutoRepeat)
            root.removed();
        event.accepted = true;
    }

    Behavior on color { ColorAnimation { duration: Theme.motionEffectsFast } }

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
        anchors.margins: Theme.toastPaddingX
        spacing: Theme.toastPaddingX

        Item {
            width: Theme.toastIconSize
            height: width
            y: (parent.height - height) / 2

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.controlFill(false, false, false)
                border.width: Theme.borderWidth
                border.color: root.urgent ? Theme.red : Theme.panelBorder
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
                color: root.selected ? Theme.menuSelectedText
                    : Theme.networkSecondary
                font.pixelSize: root.fallbackIcon !== "" ? Theme.fontTitle : Theme.fontSubtitle
                font.bold: true
            }
        }

        Column {
            width: parent.width - Theme.toastIconSize - parent.spacing
            spacing: Theme.toastTextGap

            Row {
                width: parent.width

                Line {
                    width: parent.width - age.width
                    text: (root.urgent ? "Urgent · " : "") + Notify.sourceName(root.entry)
                        + ((root.entry.count ?? 1) > 1 ? "  ×" + root.entry.count : "")
                    color: root.selected ? Theme.menuSelectedText
                        : Theme.networkSecondary
                    font.pixelSize: Theme.fontCaption
                    font.bold: true
                    elide: Text.ElideRight
                }

                Line {
                    id: age
                    visible: !hover.hovered || root.showActions
                    text: Notify.ago(root.entry.time)
                    color: Theme.networkSecondary
                }
            }

            Line {
                width: parent.width
                text: root.entry.summary || ""
                color: root.selected ? Theme.menuSelectedText : Theme.fg
                font.pixelSize: Theme.networkTitleSize
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Line {
                width: parent.width
                visible: root.detailed && text !== ""
                text: Notify.plain(root.entry.body)
                color: Theme.networkSecondary
                font.pixelSize: Theme.fontBody
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Flow {
                width: parent.width
                spacing: Theme.spaceSm
                visible: root.showActions

                ControlButton {
                    id: openButton
                    text: "Open"
                    onTriggered: root.opened()
                    onActiveFocusChanged: if (activeFocus) { root.focusEntered(); root.controlFocused(this); }
                }

                Repeater {
                    model: root.liveActions.filter(a => a.identifier !== "default")

                    ControlButton {
                        required property var modelData
                        TextMetrics {
                            id: actionText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            text: modelData.text || "Action"
                            elide: Text.ElideRight
                            elideWidth: Math.max(1, content.width - Theme.toastIconSize - content.spacing - Theme.spaceXl * 2)
                        }
                        text: actionText.elidedText
                        accessibleName: modelData.text || "Action"
                        onTriggered: Notify.invoke(root.entry.key, modelData)
                        onActiveFocusChanged: if (activeFocus) { root.focusEntered(); root.controlFocused(this); }
                    }
                }

                ControlButton {
                    id: dismissButton
                    text: "Dismiss"
                    danger: true
                    onTriggered: root.removed()
                    onActiveFocusChanged: if (activeFocus) { root.focusEntered(); root.controlFocused(this); }
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
        radius: Theme.radius
        color: Theme.controlFill(dismissHover.hovered, false, false)
        border.width: Theme.controlBorderWidth(dismissHover.hovered, false, false)
        border.color: Theme.controlBorder(dismissHover.hovered, false, false)
        z: 3

        Line {
            anchors.centerIn: parent
            text: "×"
            color: Theme.fg
            font.pixelSize: Theme.fontBody
        }

        HoverHandler { id: dismissHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.removed() }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? root.removed() : root.opened()
    }
}
