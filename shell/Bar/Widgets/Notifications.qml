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
        if (name === "notifications")
            Notify.markSeen();
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
    slotChars: 0
    label: Notify.dnd ? "DND" : "INBOX"
    icon: Notify.dnd ? Icons.bellOff : Icons.bell
    text: Notify.unreadCount > 0 ? "•" : ""
    color: Notify.dnd ? Theme.fgDim : (Notify.count > 0 ? Theme.text : Theme.textDim)

    onRightClicked: Notify.setDnd(!Notify.dnd)

    preview: Component {
        BarPreview {
            icon: Notify.dnd ? Icons.bellOff : Icons.bell
            title: "Activity"
            subtitle: Notify.dnd ? "Do not disturb" : "Notifications and clipboard"
            badge: Notify.unreadCount > 0 ? "NEW" : ""
            badgeColor: Theme.accent
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
            else {
                Runtime.notifyOpen = true;
                Notify.markSeen();
            }
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
            property bool searching: false
            property bool clearArmed: false
            property bool clipboardClearArmed: false

            readonly property real rowWidth: 56 * Theme.cellW
            readonly property int clipboardCount: Clipboard.entries.length + Clipboard.images.length
            readonly property var shownNotifications: Notify.history.filter(e => {
                const needle = panel.query.trim().toLowerCase();
                if (needle === "") return true;
                return ((e.appName || "") + " " + (e.summary || "") + " " + (e.body || "")).toLowerCase().indexOf(needle) >= 0;
            })

            function beginSearch() {
                searching = true;
                Qt.callLater(function() { search.forceActiveFocus(); });
            }

            function endSearch() {
                query = "";
                searching = false;
            }

            component HeaderAction: Rectangle {
                id: headerAction
                property string text: ""
                property bool active: false
                property bool danger: false
                property color accentColor: Theme.accent
                signal triggered()

                width: actionLabel.implicitWidth + Theme.cellW * 2
                height: Theme.controlHeight
                radius: Math.max(Theme.radius, Theme.cellH * 0.35)
                color: active ? Theme.alpha(accentColor, 0.12)
                    : (actionHover.hovered ? Theme.alpha(Theme.fg, 0.08) : "transparent")

                Behavior on color { ColorAnimation { duration: Theme.motionEffectsFast } }

                Line {
                    id: actionLabel
                    anchors.centerIn: parent
                    text: headerAction.text
                    color: headerAction.active || headerAction.danger
                        ? Theme.readable(headerAction.accentColor, Theme.bg) : Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                    font.bold: headerAction.active
                }

                HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: headerAction.triggered() }
            }

            Timer {
                id: clearReset
                interval: 3000
                onTriggered: panel.clearArmed = false
            }

            Timer {
                id: clipboardClearReset
                interval: 3000
                onTriggered: panel.clipboardClearArmed = false
            }

            spacing: Theme.cellH * 0.3

            Row {
                width: panel.rowWidth
                spacing: Theme.cellW

                HeaderAction {
                    id: notificationsTab
                    text: "Notifications"
                    active: Runtime.activityTab === "notifications"
                    onTriggered: root.selectTab("notifications")
                }

                HeaderAction {
                    id: clipboardTab
                    text: "Clipboard"
                    active: Runtime.activityTab === "clipboard"
                    onTriggered: root.selectTab("clipboard")
                }

                Item {
                    width: Math.max(0, panel.rowWidth - notificationsTab.width - clipboardTab.width - parent.spacing * 3 - activityStatus.width)
                    height: 1
                }

                Line {
                    id: activityStatus
                    anchors.verticalCenter: parent.verticalCenter
                    text: Notify.dnd ? "DO NOT DISTURB" : "ACTIVITY"
                    color: Theme.muted
                    font.pixelSize: Theme.fontCaption
                }
            }

            // Keep both pages alive inside one stable geometry. Replacing a
            // Loader's sourceComponent briefly collapses its implicit height;
            // Wayland compositors may then reposition the popup or end its
            // grab while the user is switching tabs.
            Item {
                width: panel.rowWidth
                height: Theme.cellH * 29

                Loader {
                    anchors.fill: parent
                    sourceComponent: notificationContent
                    visible: Runtime.activityTab === "notifications"
                }

                Loader {
                    anchors.fill: parent
                    sourceComponent: clipboardContent
                    visible: Runtime.activityTab === "clipboard"
                }
            }

            Component {
                id: notificationContent

                Column {
                    width: panel.rowWidth
                    spacing: Theme.cellH * 0.45

                    Row {
                        width: parent.width
                        height: Theme.controlHeight
                        spacing: Theme.cellW

                        Line {
                            width: parent.width - notificationActions.width - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: "NOTIFICATIONS"
                            color: Theme.fgDim
                            font.pixelSize: Theme.fontCaption
                            font.bold: true
                        }

                        Row {
                            id: notificationActions
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.cellW

                            HeaderAction {
                                text: panel.searching ? "Close search" : "Search"
                                active: panel.searching
                                onTriggered: panel.searching ? panel.endSearch() : panel.beginSearch()
                            }

                            HeaderAction {
                                text: Notify.dnd ? "DND on" : "DND"
                                active: Notify.dnd
                                accentColor: Theme.yellow
                                onTriggered: Notify.setDnd(!Notify.dnd)
                            }

                            HeaderAction {
                                visible: Notify.count > 0
                                text: panel.clearArmed ? "Confirm" : "Clear"
                                accentColor: Theme.red
                                danger: true
                                active: panel.clearArmed
                                onTriggered: {
                                    if (!panel.clearArmed) {
                                        panel.clearArmed = true;
                                        clearReset.restart();
                                    } else {
                                        clearReset.stop();
                                        panel.clearArmed = false;
                                        Notify.clear();
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Theme.controlHeight
                        visible: panel.searching
                        radius: Math.max(Theme.radius, Theme.cellH * 0.45)
                        color: Theme.alpha(Theme.fg, 0.06)
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
                            Keys.onEscapePressed: panel.endSearch()

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
                        visible: panel.shownNotifications.length === 0
                        text: Notify.count > 0 ? "No matching notifications" : "No notifications yet"
                        color: Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Flickable {
                        id: historyView
                        width: parent.width
                        height: panel.shownNotifications.length > 0 ? Theme.cellH * 25 : 0
                        visible: panel.shownNotifications.length > 0
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
                            spacing: Theme.cellH * 0.4

                            Repeater {
                                model: panel.shownNotifications

                                Column {
                                    required property var modelData
                                    required property int index
                                    width: historyCards.width
                                    spacing: Theme.cellH * 0.35

                                    Line {
                                        visible: parent.index === 0
                                            || Notify.dayLabel(panel.shownNotifications[parent.index - 1].time)
                                                !== Notify.dayLabel(parent.modelData.time)
                                        width: parent.width
                                        height: visible ? Theme.cellH * 1.25 : 0
                                        text: Notify.dayLabel(parent.modelData.time)
                                        color: Theme.fgDim
                                        font.pixelSize: Theme.fontCaption
                                        font.bold: true
                                        verticalAlignment: Text.AlignBottom
                                    }

                                    NotificationCard {
                                        width: parent.width
                                        entry: parent.modelData
                                        detailed: true
                                        showActions: false
                                        unread: parent.modelData.time.getTime() > Notify.readMark
                                        onOpened: { Notify.focus(parent.modelData); panel.closePopout?.(); }
                                        onRemoved: Notify.drop(parent.modelData.key)
                                    }
                                }
                            }
                        }
                    }

                    Line {
                        visible: Notify.count > 0
                        width: parent.width
                        text: Notify.count + " notifications kept · " + Notify.keepDays + " days"
                        color: Theme.muted
                        font.pixelSize: Theme.fontCaption
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Component {
                id: clipboardContent

                Column {
                    width: panel.rowWidth
                    spacing: Theme.cellH * 0.45

                    Row {
                        width: parent.width
                        height: Theme.controlHeight
                        spacing: Theme.cellW

                        Line {
                            width: parent.width - clearClipboard.width - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: "CLIPBOARD"
                            color: Theme.fgDim
                            font.pixelSize: Theme.fontCaption
                            font.bold: true
                        }

                        HeaderAction {
                            id: clearClipboard
                            visible: panel.clipboardCount > 0
                            text: panel.clipboardClearArmed ? "Confirm" : "Clear"
                            accentColor: Theme.red
                            danger: true
                            active: panel.clipboardClearArmed
                            onTriggered: {
                                if (!panel.clipboardClearArmed) {
                                    panel.clipboardClearArmed = true;
                                    clipboardClearReset.restart();
                                } else {
                                    clipboardClearReset.stop();
                                    panel.clipboardClearArmed = false;
                                    Clipboard.clear();
                                }
                            }
                        }
                    }

                    Line {
                        visible: panel.clipboardCount === 0
                        width: parent.width
                        text: "Nothing copied yet"
                        color: Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Flickable {
                        id: clipboardView
                        width: parent.width
                        height: panel.clipboardCount > 0 ? Theme.cellH * 25 : 0
                        visible: panel.clipboardCount > 0
                        contentHeight: clipboardCards.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            width: Math.max(Theme.borderWidth * 3, 4)
                            policy: clipboardView.contentHeight > clipboardView.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            contentItem: Rectangle { color: Theme.accent; radius: Theme.radius }
                            background: Rectangle { color: Theme.muted; radius: Theme.radius }
                        }

                        Column {
                            id: clipboardCards
                            width: clipboardView.width - (clipboardView.contentHeight > clipboardView.height ? Theme.cellW : 0)
                            spacing: Theme.cellH * 0.4

                            Line {
                                visible: Clipboard.images.length > 0
                                width: parent.width
                                height: visible ? Theme.cellH * 1.2 : 0
                                text: "IMAGES"
                                color: Theme.fgDim
                                font.pixelSize: Theme.fontCaption
                                font.bold: true
                                verticalAlignment: Text.AlignBottom
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
                                        radius: Math.max(Theme.radius, Theme.cellH * 0.5)
                                        color: Theme.alpha(Theme.fg, imageHover.hovered ? 0.11 : 0.06)
                                        clip: true

                                        Behavior on color { ColorAnimation { duration: Theme.motionEffectsFast } }

                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: Theme.cellW * 0.45
                                            source: Clipboard.imagePath(imageRow.modelData)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                            cache: false
                                        }

                                        Rectangle {
                                            visible: imageHover.hovered
                                            anchors.right: parent.right
                                            anchors.rightMargin: Theme.cellW * 0.4
                                            anchors.top: parent.top
                                            anchors.topMargin: Theme.cellH * 0.25
                                            width: Theme.cellH
                                            height: width
                                            radius: width / 2
                                            color: imageDismissHover.hovered ? Theme.alpha(Theme.fg, 0.24) : Theme.alpha(Theme.bg, 0.72)
                                            z: 3
                                            Line { anchors.centerIn: parent; text: "×"; color: Theme.fg }
                                            HoverHandler { id: imageDismissHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler { onTapped: Clipboard.removeImage(imageRow.modelData) }
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

                            Line {
                                visible: Clipboard.entries.length > 0
                                width: parent.width
                                height: visible ? Theme.cellH * 1.2 : 0
                                text: "TEXT"
                                color: Theme.fgDim
                                font.pixelSize: Theme.fontCaption
                                font.bold: true
                                verticalAlignment: Text.AlignBottom
                            }

                            Repeater {
                                model: Clipboard.entries.slice(0, 30)

                                Rectangle {
                                    id: clipboardRow
                                    required property var modelData
                                    required property int index
                                    width: clipboardCards.width
                                    implicitHeight: clipboardText.implicitHeight + Theme.cellH * 1.25
                                    radius: Math.max(Theme.radius, Theme.cellH * 0.58)
                                    color: Theme.alpha(Theme.fg, clipboardHover.hovered ? 0.11 : 0.06)

                                    Behavior on color { ColorAnimation { duration: Theme.motionEffectsFast } }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.cellW * 0.8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.cellH * 1.65
                                        height: width
                                        radius: Math.max(Theme.radius, Theme.cellH * 0.42)
                                        color: clipboardRow.index === 0
                                            ? Theme.alpha(Theme.accent, 0.16) : Theme.alpha(Theme.fg, 0.08)

                                        Line {
                                            anchors.centerIn: parent
                                            text: String(clipboardRow.index + 1)
                                            color: clipboardRow.index === 0 ? Theme.readable(Theme.accent, Theme.bg) : Theme.fgDim
                                            font.pixelSize: Theme.fontCaption
                                            font.bold: clipboardRow.index === 0
                                        }
                                    }

                                    Line {
                                        id: clipboardText
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.cellW * 6
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.cellW * 3
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Clipboard.preview(clipboardRow.modelData, 120)
                                        color: Theme.fg
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: clipboardHover.hovered
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.cellW * 0.7
                                        anchors.top: parent.top
                                        anchors.topMargin: Theme.cellH * 0.45
                                        width: Theme.cellH * 1.05
                                        height: width
                                        radius: width / 2
                                        color: clipboardDismissHover.hovered ? Theme.alpha(Theme.fg, 0.24) : Theme.alpha(Theme.fg, 0.13)
                                        z: 3
                                        Line { anchors.centerIn: parent; text: "×"; color: Theme.fg }
                                        HoverHandler { id: clipboardDismissHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: Clipboard.remove(clipboardRow.modelData) }
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

                    Line {
                        visible: panel.clipboardCount > 0
                        width: parent.width
                        text: panel.clipboardCount + " clipboard items kept locally"
                        color: Theme.muted
                        font.pixelSize: Theme.fontCaption
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
