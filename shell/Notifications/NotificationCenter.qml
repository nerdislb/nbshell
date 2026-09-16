import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Widgets/FocusScroll.js" as FocusScroll

PanelWindow {
    id: root
    property string query: ""
    property string selectedKey: ""
    readonly property int selected: shown.findIndex(entry => entry.key === selectedKey)
    property bool clearArmed: false
    readonly property var shown: Notify.history.filter(entry => {
        const needle = query.trim().toLowerCase();
        return needle === "" || (Notify.sourceName(entry) + " " + (entry.summary || "") + " " + Notify.plain(entry.body || "")).toLowerCase().includes(needle);
    })

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:notification-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.notificationCenterOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { cancelClear(); Runtime.notificationCenterOpen = false; }
    function requestClose(done) { cancelClear(); box.dismiss(done); }
    function requestOpen() { box.enter(); Qt.callLater(() => search.forceActiveFocus()); }
    function dropSelected() {
        if (shown[selected]) Notify.drop(selectedKey);
    }
    function openSelected() {
        if (shown[selected]) {
            Notify.open(shown[selected]);
            close();
        }
    }
    function cancelClear() { clearArmed = false; clearReset.stop(); }
    function requestClear() {
        if (!Notify.count) return;
        if (!clearArmed) {
            clearArmed = true;
            clearReset.restart();
            return;
        }
        cancelClear();
        Notify.clear();
    }
    function handleEscape() {
        if (clearArmed) cancelClear();
        else if (query !== "") query = "";
        else close();
    }
    function moveSelection(delta) {
        if (!shown.length) return;
        const next = Math.max(0, Math.min(shown.length - 1, Math.max(0, selected) + delta));
        selectedKey = shown[next].key;
        flick.forceActiveFocus(Qt.TabFocusReason);
    }
    onQueryChanged: {
        Qt.callLater(() => { selectedKey = shown.length ? shown[0].key : ""; });
        cancelClear();
    }
    onShownChanged: {
        // Incoming notifications must not redirect a pending Open/Dismiss.
        Qt.callLater(() => {
            if (!shown.some(entry => entry.key === selectedKey))
                selectedKey = shown.length ? shown[0].key : "";
            flick.revealSelected();
            // Repeater replacement can destroy a focused per-card action.
            if (!search.activeFocus && !dnd.activeFocus && !clearButton.activeFocus) flick.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    onSelectedChanged: Qt.callLater(() => flick.revealSelected())
    Component.onCompleted: Qt.callLater(() => search.forceActiveFocus())

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: event => { root.handleEscape(); event.accepted = true; }

        OverlaySurface {
            id: box
            // Omarchy's centered history-panel frame. Full notification history
            // is a native extension; see docs/notification-center-parity.md.
            preferredWidth: Theme.activityWidth
            preferredHeight: Theme.activityHeight
            color: Theme.bg
            border.width: Theme.networkBorderWidth
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.activityPadding + box.border.width
                spacing: Theme.activityGap
                Row {
                    id: header
                    width: parent.width
                    spacing: Theme.spaceSm
                    Line {
                        width: Math.max(0, parent.width - controls.width - parent.spacing)
                        height: Theme.controlHeight
                        verticalAlignment: Text.AlignVCenter
                        text: "Notifications · " + Notify.count
                        color: Theme.fg
                        font.pixelSize: Theme.activityHeadingSize
                        elide: Text.ElideRight
                    }
                    Row {
                        id: controls
                        spacing: Theme.spaceSm
                        ControlButton {
                            id: dnd
                            text: Notify.dnd ? "DND on" : "DND off"
                            selected: Notify.dnd
                            accessibleCheckable: true
                            accessibleChecked: Notify.dnd
                            onTriggered: Notify.setDnd(!Notify.dnd)
                        }
                        ControlButton {
                            id: clearButton
                            text: root.clearArmed ? "Confirm clear" : "Clear all"
                            danger: true
                            selected: root.clearArmed
                            enabled: Notify.count > 0
                            onTriggered: root.requestClear()
                        }
                    }
                }
                TextField {
                    id: search
                    width: parent.width
                    height: Theme.activitySearchHeight
                    accessibleName: "Search notifications"
                    placeholderText: "Search notifications…"
                    text: root.query
                    onTextEdited: root.query = text
                    Keys.onDownPressed: root.moveSelection(0)
                    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.openSelected(); }
                    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.openSelected(); }
                }
                Flickable {
                    id: flick
                    width: parent.width
                    height: Math.max(1, parent.height - header.height - search.height - footer.height - 3 * parent.spacing)
                    contentHeight: cards.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    activeFocusOnTab: true
                    KeyNavigation.tab: notificationCards.itemAt(root.selected)?.firstAction ?? null
                    Accessible.role: Accessible.List
                    Accessible.name: "Notification history"
                    Accessible.description: root.shown[root.selected]?.summary || "Empty"
                    Accessible.focusable: true
                    Accessible.focused: activeFocus
                    Keys.onPressed: event => {
                        let handled = true;
                        if (event.isAutoRepeat && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Delete, Qt.Key_X, Qt.Key_D, Qt.Key_C].includes(event.key)) { event.accepted = true; return; }
                        if (event.key === Qt.Key_C && event.modifiers === Qt.ControlModifier) root.requestClear();
                        else if (event.modifiers !== Qt.NoModifier) handled = false;
                        else if (event.key === Qt.Key_Up) root.moveSelection(-1);
                        else if (event.key === Qt.Key_Down) root.moveSelection(1);
                        else if ((event.key === Qt.Key_Home || event.key === Qt.Key_End) && root.shown.length)
                            root.selectedKey = root.shown[event.key === Qt.Key_Home ? 0 : root.shown.length - 1].key;
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.openSelected();
                        else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) root.dropSelected();
                        else if (event.key === Qt.Key_D) Notify.setDnd(!Notify.dnd);
                        else handled = false;
                        event.accepted = handled;
                    }
                    function revealSelected() { revealItem(notificationCards.itemAt(root.selected)); }
                    function revealItem(item) {
                        if (!item) return;
                        const mapped = item.mapToItem(cards, 0, 0);
                        contentY = FocusScroll.contentYForFocus(
                            mapped.y, item.height, contentY, height, contentHeight, Theme.spaceMd);
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Column {
                        id: cards
                        width: flick.width - Theme.spaceSm
                        spacing: Theme.activityGap
                        Repeater {
                            id: notificationCards
                            model: root.shown
                            NotificationCard {
                                id: card
                                required property var modelData
                                required property int index
                                width: cards.width
                                entry: modelData
                                selected: modelData.key === root.selectedKey
                                keyboardSelected: selected && flick.activeFocus
                                onOpened: { Notify.open(modelData); root.close(); }
                                onRemoved: Notify.drop(modelData.key)
                                onFocusEntered: {
                                    root.selectedKey = modelData.key;
                                }
                                onControlFocused: control => Qt.callLater(() => flick.revealItem(control))
                            }
                        }
                    }
                    Column {
                        parent: flick
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: Theme.spaceMd
                        visible: root.shown.length === 0
                        Line {
                            width: parent.width
                            text: Icons.bell
                            font.pixelSize: Theme.fontDisplay
                            color: Theme.networkSecondary
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Line {
                            width: parent.width
                            text: Notify.count ? "No matches" : "No notifications yet"
                            color: Theme.networkSecondary
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
                Line {
                    id: footer
                    width: parent.width
                    text: root.clearArmed ? "Clear all notifications? Activate again to confirm · Esc cancels"
                        : "↑↓ select · Enter open · x/Del dismiss · d DND · Ctrl+c twice clears · Esc"
                    color: Theme.networkSecondary
                    font.pixelSize: Theme.fontCaption
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Timer { id: clearReset; interval: 3000; onTriggered: root.clearArmed = false }
}
