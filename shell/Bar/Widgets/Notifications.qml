import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Notifications
import qs.Services
import qs.Widgets

// One quiet bar entry for the two closely related inboxes. Existing notify
// and clipboard IPC commands still open their respective tab directly.
Cell {
    id: root

    function selectTab(name) {
        Runtime.activityTab = name;
        if (!root.popoutVisible)
            return;
        // Set the destination first so the old IPC flag can be cleared
        // without briefly closing the shared popout.
        if (name === "clipboard") {
            Runtime.clipOpen = true;
            Runtime.notifyOpen = false;
        } else {
            Runtime.notifyOpen = true;
            Runtime.clipOpen = false;
        }
    }

    interactive: true
    quiet: false
    slotChars: 1
    label: Notify.dnd ? "DND" : "INBOX"
    icon: Notify.dnd ? Icons.bellOff : Icons.bell
    text: ""
    color: Notify.dnd ? Theme.fgDim : (Notify.count > 0 ? Theme.text : Theme.textDim)

    onRightClicked: Notify.setDnd(!Notify.dnd)

    preview: Component {
        BarPreview {
            icon: Notify.dnd ? Icons.bellOff : Icons.bell
            title: "Activity"
            subtitle: Notify.dnd ? "Do not disturb" : "Notifications and clipboard"
            badge: String(Notify.count)
            badgeColor: Notify.count > 0 ? Theme.accent : Theme.fgDim
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Notifications", "value": String(Notify.count) },
                        { "label": "Clipboard", "value": String(Clipboard.entries.length + Clipboard.images.length) }
                    ]
                },
                Repeater {
                    model: Notify.history.slice(0, 2)
                    Line {
                        required property var modelData
                        width: parent.width
                        text: (modelData.appName || "Message") + "  ·  " + (modelData.summary || modelData.body || "")
                        color: Theme.fg
                        elide: Text.ElideRight
                    }
                }
            ]
        }
    }

    onPopoutVisibleChanged: {
        if (root.popoutVisible) {
            if (Runtime.activityTab === "clipboard")
                Runtime.clipOpen = true;
            else
                Runtime.notifyOpen = true;
        } else {
            Runtime.notifyOpen = false;
            Runtime.clipOpen = false;
        }
    }

    Connections {
        target: Runtime

        function onNotifyOpenChanged() {
            if (Runtime.notifyOpen) {
                Runtime.activityTab = "notifications";
                Runtime.clipOpen = false;
                root.setPopout(true);
            } else if (!Runtime.clipOpen) {
                root.setPopout(false);
            }
        }

        function onClipOpenChanged() {
            if (Runtime.clipOpen) {
                Runtime.activityTab = "clipboard";
                Runtime.notifyOpen = false;
                root.setPopout(true);
            } else if (!Runtime.notifyOpen) {
                root.setPopout(false);
            }
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null
            property string query: ""

            readonly property real rowWidth: 54 * Theme.cellW
            readonly property int clipboardCount: Clipboard.entries.length + Clipboard.images.length
            readonly property var shownNotifications: Notify.history.filter(e => {
                const needle = panel.query.trim().toLowerCase();
                if (needle === "") return true;
                return ((e.appName || "") + " " + (e.summary || "") + " " + (e.body || "")).toLowerCase().indexOf(needle) >= 0;
            })

            spacing: Theme.cellH * 0.3

            Row {
                width: panel.rowWidth
                spacing: Theme.cellW

                ActionButton {
                    width: (panel.rowWidth - parent.spacing) / 2
                    text: "Notifications"
                    tone: Runtime.activityTab === "notifications" ? "primary" : "secondary"
                    onTriggered: root.selectTab("notifications")
                }

                ActionButton {
                    width: (panel.rowWidth - parent.spacing) / 2
                    text: "Clipboard"
                    tone: Runtime.activityTab === "clipboard" ? "primary" : "secondary"
                    onTriggered: root.selectTab("clipboard")
                }
            }

            Loader {
                width: panel.rowWidth
                sourceComponent: Runtime.activityTab === "clipboard" ? clipboardContent : notificationContent
            }

            Component {
                id: notificationContent

                Column {
                    width: panel.rowWidth
                    spacing: Theme.cellH * 0.3

                    Item {
                        width: parent.width
                        height: Theme.cellH * 2.6

                        PanelHead {
                            anchors.left: parent.left
                            rowWidth: parent.width - notificationActions.width - Theme.spaceLg
                            icon: Notify.dnd ? Icons.bellOff : Icons.bell
                            title: "Notifications"
                            subtitle: Notify.dnd ? "Do not disturb" : "Recent messages"
                            badge: String(Notify.count)
                        }

                        Row {
                            id: notificationActions
                            anchors.right: parent.right
                            spacing: Theme.cellW

                            ActionButton {
                                text: Notify.dnd ? "DND on" : "Muted"
                                tone: Notify.dnd ? "primary" : "secondary"
                                accentColor: Theme.yellow
                                compact: true
                                onTriggered: Notify.setDnd(!Notify.dnd)
                            }

                            ActionButton {
                                visible: Notify.count > 0
                                text: "Clear"
                                tone: "danger"
                                compact: true
                                onTriggered: Notify.clear()
                            }
                        }
                    }

                    Line {
                        visible: Notify.count === 0
                        text: "nothing here"
                        color: Theme.muted
                    }

                    Rectangle {
                        width: parent.width
                        height: Theme.controlHeight
                        visible: Notify.count > 0
                        radius: Theme.radius
                        color: Theme.panelSurfaceRaised
                        border.width: Theme.borderWidth
                        border.color: search.activeFocus ? Theme.focusBorder : Theme.panelBorder

                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: Theme.cellW
                            anchors.rightMargin: Theme.cellW
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            text: panel.query
                            onTextChanged: panel.query = text

                            Line {
                                anchors.fill: parent
                                visible: parent.text === "" && !parent.activeFocus
                                verticalAlignment: Text.AlignVCenter
                                text: "Search notifications …"
                                color: Theme.muted
                            }
                        }
                    }

                    Line {
                        visible: Notify.count > 0 && panel.shownNotifications.length === 0
                        text: "no results"
                        color: Theme.muted
                    }

                    Flickable {
                        id: historyView
                        width: parent.width
                        height: Notify.count > 0 ? Theme.cellH * 20 : 0
                        visible: Notify.count > 0
                        contentHeight: historyCards.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            width: Math.max(Theme.borderWidth * 3, 4)
                            policy: historyView.contentHeight > historyView.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            contentItem: Rectangle { color: Theme.accent; radius: Theme.radius }
                            background: Rectangle { color: Theme.muted; radius: Theme.radius }
                        }

                        Column {
                            id: historyCards
                            width: historyView.width - (historyView.contentHeight > historyView.height ? Theme.cellW : 0)
                            spacing: Theme.cellH * 0.3

                            Repeater {
                                model: panel.shownNotifications

                                NotificationCard {
                                    required property var modelData
                                    width: historyCards.width
                                    entry: modelData
                                    detailed: false
                                    onOpened: { Notify.open(modelData); panel.closePopout?.(); }
                                    onRemoved: Notify.drop(modelData.key)
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: clipboardContent

                Column {
                    width: panel.rowWidth
                    spacing: Theme.cellH * 0.2

                    Item {
                        width: parent.width
                        height: Theme.cellH * 2.6

                        PanelHead {
                            anchors.left: parent.left
                            rowWidth: parent.width - clearButton.width - Theme.spaceLg
                            icon: Icons.clipboard
                            title: "Clipboard"
                            subtitle: "Recent text and images"
                            badge: String(panel.clipboardCount)
                        }

                        ActionButton {
                            id: clearButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: panel.clipboardCount > 0
                            text: "Clear"
                            tone: "danger"
                            compact: true
                            onTriggered: Clipboard.clear()
                        }
                    }

                    Line {
                        visible: panel.clipboardCount === 0
                        text: "nothing copied yet"
                        color: Theme.muted
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.cellW
                        visible: Clipboard.images.length > 0

                        Repeater {
                            model: Clipboard.images.slice(0, 8)

                            Rectangle {
                                id: imageRow
                                required property var modelData
                                width: Theme.cellW * 12
                                height: Theme.cellH * 5
                                radius: Theme.radius
                                color: imageHover.hovered ? Theme.hover : Theme.panelSurfaceRaised
                                border.width: Theme.borderWidth
                                border.color: Theme.panelBorder
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: Theme.borderWidth
                                    source: Clipboard.imagePath(imageRow.modelData)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                }

                                HoverHandler { id: imageHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onTapped: (point, button) => {
                                        if (button === Qt.RightButton)
                                            Clipboard.removeImage(imageRow.modelData);
                                        else {
                                            Clipboard.copyImage(imageRow.modelData);
                                            panel.closePopout?.();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: Clipboard.entries.slice(0, 15)

                        Rectangle {
                            id: clipboardRow
                            required property var modelData
                            required property int index
                            width: panel.rowWidth
                            height: Theme.cellH * 1.4
                            radius: Theme.radius
                            color: clipboardRow.index === 0 ? Theme.selectedSurface(Theme.accent)
                                : (clipboardHover.hovered ? Theme.hover : "transparent")
                            border.width: clipboardRow.index === 0 ? Theme.borderWidth : 0
                            border.color: Theme.focusBorder

                            Line {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.cellW / 2
                                anchors.verticalCenter: parent.verticalCenter
                                text: (clipboardRow.index < 9 ? (clipboardRow.index + 1) + "  " : "   ") + Clipboard.preview(clipboardRow.modelData, 46)
                                color: clipboardRow.index === 0 ? Theme.selectedForeground(Theme.accent) : Theme.fg
                                elide: Text.ElideRight
                            }

                            HoverHandler { id: clipboardHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onTapped: (point, button) => {
                                    if (button === Qt.RightButton)
                                        Clipboard.remove(clipboardRow.modelData);
                                    else {
                                        Clipboard.copy(clipboardRow.modelData);
                                        panel.closePopout?.();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
