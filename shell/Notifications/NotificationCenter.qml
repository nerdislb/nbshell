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
    property int selected: 0
    property bool clearArmed: false
    readonly property var shown: Notify.history.filter(entry => {
        const needle = query.trim().toLowerCase();
        return needle === "" || ((entry.appName || "") + " " + (entry.summary || "") + " " + (entry.body || "")).toLowerCase().indexOf(needle) >= 0;
    })

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:notification-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.notificationCenterOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.notificationCenterOpen = false; }
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }
    function dropSelected() {
        if (shown[selected]) Notify.drop(shown[selected].key);
    }
    function openSelected() {
        if (shown[selected]) {
            Notify.open(shown[selected]);
            close();
        }
    }
    function requestClear() {
        if (!clearArmed) {
            clearArmed = true;
            clearReset.restart();
            return;
        }
        clearReset.stop();
        clearArmed = false;
        Notify.clear();
    }
    onVisibleChanged: if (visible) { query = ""; selected = 0; clearArmed = false; keys.forceActiveFocus(); }
    onQueryChanged: {
        selected = 0;
        Qt.callLater(() => flick.revealSelected());
    }
    onShownChanged: {
        selected = Math.max(0, Math.min(selected, shown.length - 1));
        Qt.callLater(() => flick.revealSelected());
    }
    onSelectedChanged: Qt.callLater(() => flick.revealSelected())

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onPressed: event => {
            let handled = true;
            if (event.key === Qt.Key_Escape) root.query !== "" ? root.query = "" : root.close();
            else if (event.key === Qt.Key_Backspace) root.query = root.query.slice(0, -1);
            else if (event.key === Qt.Key_Up) root.selected = Math.max(0, root.selected - 1);
            else if (event.key === Qt.Key_Down && root.shown.length > 0)
                root.selected = Math.min(root.shown.length - 1, root.selected + 1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.openSelected();
            else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) root.dropSelected();
            else if (event.key === Qt.Key_D) Notify.setDnd(!Notify.dnd);
            else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) root.requestClear();
            else if (event.text && event.text >= " ") root.query += event.text;
            else handled = false;
            event.accepted = handled;
        }

        OverlaySurface {
            id: box
            // Breiter fuer klare Kartenzeilen, aber bewusst nur rund ein
            // halber Bildschirm hoch. Der Verlauf scrollt innerhalb der Box.
            preferredWidth: Theme.cellW * 116
            preferredHeight: Theme.cellH * 31
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH * 0.4
                Row {
                    width: parent.width
                    Line { width: parent.width - controls.width; text: Icons.bell + "  NOTIFICATIONS  (" + Notify.count + ")"; color: Theme.fg; font.pixelSize: Theme.fontHeading; font.bold: true }
                    Row {
                        id: controls
                        spacing: Theme.cellW
                        ActionButton { text: Notify.dnd ? "DND on" : "DND off"; tone: Notify.dnd ? "primary" : "secondary"; compact: true; accentColor: Theme.yellow; onTriggered: Notify.setDnd(!Notify.dnd) }
                        ActionButton {
                            text: root.clearArmed ? "Confirm clear" : "Clear all"
                            tone: "danger"
                            compact: true
                            enabled: Notify.count > 0
                            onTriggered: root.requestClear()
                        }
                    }
                }
                Rectangle {
                    width: parent.width; height: Theme.controlHeight; radius: Theme.radius; color: Theme.panelSurfaceRaised
                    border.width: Theme.borderWidth; border.color: root.query !== "" ? Theme.focusBorder : Theme.panelBorder
                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: root.query !== "" ? root.query : "Type to search …"; color: root.query !== "" ? Theme.fg : Theme.muted }
                }
                Rule { rowWidth: parent.width }
                Flickable {
                    id: flick
                    width: parent.width
                    height: parent.height - Theme.cellH * 8
                    contentHeight: cards.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    function revealSelected() {
                        const item = notificationCards.itemAt(root.selected);
                        if (!item)
                            return;
                        const mapped = item.mapToItem(cards, 0, 0);
                        contentY = FocusScroll.contentYForFocus(
                            mapped.y, item.height, contentY, height, contentHeight, Theme.spaceMd);
                    }
                    ScrollBar.vertical: ScrollBar {
                        width: Math.max(Theme.borderWidth * 3, 4)
                        policy: flick.contentHeight > flick.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                        contentItem: Rectangle { color: Theme.accent; radius: Theme.radius }
                        background: Rectangle { color: Theme.muted; radius: Theme.radius }
                    }
                    Column {
                        id: cards
                        width: flick.width
                        spacing: Theme.cellH * 0.3
                        Line { visible: root.shown.length === 0; text: Notify.count ? "No results" : "No notifications yet"; color: Theme.muted }
                        Repeater {
                            id: notificationCards
                            model: root.shown
                            NotificationCard {
                                id: card
                                required property var modelData
                                required property int index
                                width: cards.width
                                entry: modelData
                                selected: index === root.selected
                                onOpened: { Notify.open(modelData); root.close(); }
                                onRemoved: Notify.drop(modelData.key)
                                HoverHandler { onHoveredChanged: if (hovered) root.selected = index }
                                onActiveFocusChanged: if (activeFocus) root.selected = index
                                onFocusEntered: root.selected = index
                            }
                        }
                    }
                }
                Line { text: "↑↓ select · x/Del remove · d DND · Ctrl+c twice clears · type to search · Esc"; color: Theme.muted }
            }
        }
    }

    Timer {
        id: clearReset
        interval: 3000
        onTriggered: root.clearArmed = false
    }
}
