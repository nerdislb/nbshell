import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root
    property string query: ""
    property int selected: 0
    readonly property var shown: Notify.history.filter(entry => {
        const needle = query.trim().toLowerCase();
        return needle === "" || ((entry.appName || "") + " " + (entry.summary || "") + " " + (entry.body || "")).toLowerCase().indexOf(needle) >= 0;
    })

    visible: Runtime.notificationCenterOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:notification-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.notificationCenterOpen = false; }
    function dropSelected() {
        if (shown[selected]) Notify.drop(shown[selected].key);
        selected = Math.max(0, Math.min(selected, shown.length - 2));
    }
    onVisibleChanged: if (visible) { query = ""; selected = 0; keys.forceActiveFocus(); }
    onQueryChanged: selected = 0

    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bgDarker, 0.78) }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.query !== "" ? root.query = "" : root.close();
            else if (event.key === Qt.Key_Backspace) root.query = root.query.slice(0, -1);
            else if (event.key === Qt.Key_Up) root.selected = Math.max(0, root.selected - 1);
            else if (event.key === Qt.Key_Down) root.selected = Math.min(root.shown.length - 1, root.selected + 1);
            else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) root.dropSelected();
            else if (event.key === Qt.Key_D) Notify.setDnd(!Notify.dnd);
            else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) Notify.clear();
            else if (event.text && event.text >= " ") root.query += event.text;
            event.accepted = true;
        }

        Rectangle {
            id: box
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.cellW * 8, Theme.cellW * 100)
            height: Math.min(parent.height - Theme.cellH * 6, Theme.cellH * 43)
            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH * 0.4
                Row {
                    width: parent.width
                    Line { width: parent.width - controls.width; text: Icons.bell + "  BENACHRICHTIGUNGEN  (" + Notify.count + ")"; color: Theme.fg; font.pixelSize: Theme.fontSize + 3 }
                    Row {
                        id: controls
                        spacing: Theme.cellW
                        ActionButton { text: Notify.dnd ? "DND an" : "DND aus"; tone: Notify.dnd ? "primary" : "secondary"; compact: true; accentColor: Theme.yellow; onTriggered: Notify.setDnd(!Notify.dnd) }
                        ActionButton { text: "Alles leeren"; tone: "danger"; compact: true; enabled: Notify.count > 0; onTriggered: Notify.clear() }
                    }
                }
                Rectangle {
                    width: parent.width; height: Theme.cellH * 2; radius: Theme.radius; color: Theme.bgLight
                    border.width: Theme.borderWidth; border.color: root.query !== "" ? Theme.accent : Theme.muted
                    Line { anchors.left: parent.left; anchors.leftMargin: Theme.cellW; anchors.verticalCenter: parent.verticalCenter; text: root.query !== "" ? root.query : "Tippen zum Suchen …"; color: root.query !== "" ? Theme.fg : Theme.muted }
                }
                Rule { rowWidth: parent.width }
                Flickable {
                    id: flick
                    width: parent.width
                    height: parent.height - Theme.cellH * 8
                    contentHeight: cards.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: cards
                        width: flick.width
                        spacing: Theme.cellH * 0.3
                        Line { visible: root.shown.length === 0; text: Notify.count ? "Kein Treffer" : "Noch keine Benachrichtigungen"; color: Theme.muted }
                        Repeater {
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
                            }
                        }
                    }
                }
                Line { text: "↑↓ wählen · x/Entf löschen · d DND · Ctrl+c alles leeren · Tippen sucht · Esc"; color: Theme.muted }
            }
        }
    }
}
