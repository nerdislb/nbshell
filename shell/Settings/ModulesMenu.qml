import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Bausteine anordnen -- links die vier Gruppen mit ihrem Inhalt, rechts alles,
// was es gibt.
//
// Genau das, was in der DankBar das Ziehen und Ablegen macht, nur mit Tasten:
// `←→` verschiebt innerhalb der Gruppe, `Shift+←→` in die Nachbargruppe, `x`
// wirft raus. Tab wechselt in die Liste rechts, Enter haengt von dort an.
//
// Damit loest sich auch die Frage "warum ist die Uhr nicht mittig": mittig
// steht die MITTELGRUPPE als Ganzes. Liegt noch etwas anderes darin, sitzt die
// Uhr eben daneben -- hier laesst es sich in einem Zug woanders hinlegen.
PanelWindow {
    id: root

    readonly property var groups: [
        {
            "key": "collapsedWidgets",
            "label": "Collapsed (island)"
        },
        {
            "key": "leftWidgets",
            "label": "Left"
        },
        {
            "key": "centerWidgets",
            "label": "Center"
        },
        {
            "key": "rightWidgets",
            "label": "Right"
        }
    ]

    // Der Vorrat kommt aus dem Katalog: eingebaute Bausteine und alles, was
    // unter ~/.config/nbshell/plugins liegt. Hier steht KEINE Liste mehr --
    // ein eigener Baustein taucht auf, sobald sein Verzeichnis da ist.
    readonly property var catalog: Plugins.ids

    // Feste Breiten am Fenster statt `width: <Column>.width` an den Zeilen:
    // die Verweise vom Kind auf den Positionierer haben hier dazu gefuehrt,
    // dass die Zeilen gar nicht erst entstanden -- ohne Fehler, ohne Meldung.
    readonly property real leftWidth: Theme.cellW * 46
    readonly property real rightWidth: Theme.cellW * 24

    property int groupIndex: 0
    property int itemIndex: 0
    property bool inCatalog: false
    property int catalogIndex: 0
    property int dragGroup: -1
    property int dragIndex: -1

    readonly property var currentList: Config.value(groups[groupIndex].key, [])

    visible: Runtime.modulesOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:modules"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.modulesOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.modulesOpen = false;
    }

    function listOf(i) {
        return Config.value(groups[i].key, []).slice();
    }

    function save(i, list) {
        Config.set(groups[i].key, list);
    }

    // Innerhalb der Gruppe schieben.
    function moveWithin(delta) {
        const list = listOf(groupIndex);
        const target = itemIndex + delta;
        if (target < 0 || target >= list.length)
            return;
        const item = list.splice(itemIndex, 1)[0];
        list.splice(target, 0, item);
        save(groupIndex, list);
        itemIndex = target;
    }

    // In die Nachbargruppe schieben -- ans Ende, dort faellt es auf.
    function moveToGroup(delta) {
        const from = listOf(groupIndex);
        if (itemIndex >= from.length)
            return;
        const target = groupIndex + delta;
        if (target < 0 || target >= groups.length)
            return;
        const item = from.splice(itemIndex, 1)[0];
        save(groupIndex, from);
        const to = listOf(target);
        to.push(item);
        save(target, to);
        groupIndex = target;
        itemIndex = to.length - 1;
    }

    function removeItem() {
        const list = listOf(groupIndex);
        if (itemIndex >= list.length)
            return;
        list.splice(itemIndex, 1);
        save(groupIndex, list);
        itemIndex = Math.max(0, Math.min(itemIndex, list.length - 1));
    }

    function moveDragged(toGroup, toIndex) {
        if (dragGroup < 0 || dragIndex < 0 || toGroup < 0 || toGroup >= groups.length)
            return;
        const fromGroup = dragGroup;
        const fromIndex = dragIndex;
        const from = listOf(fromGroup);
        if (fromIndex >= from.length)
            return;
        const item = from.splice(fromIndex, 1)[0];
        if (fromGroup === toGroup) {
            var adjusted = Math.max(0, Math.min(toIndex, from.length));
            if (fromIndex < toIndex)
                adjusted = Math.max(0, adjusted - 1);
            from.splice(adjusted, 0, item);
            save(fromGroup, from);
            groupIndex = fromGroup;
            itemIndex = adjusted;
        } else {
            save(fromGroup, from);
            const to = listOf(toGroup);
            const target = Math.max(0, Math.min(toIndex, to.length));
            to.splice(target, 0, item);
            save(toGroup, to);
            groupIndex = toGroup;
            itemIndex = target;
        }
        inCatalog = false;
        dragGroup = -1;
        dragIndex = -1;
    }

    function addFromCatalog() {
        const list = listOf(groupIndex);
        list.push(catalog[catalogIndex]);
        save(groupIndex, list);
        itemIndex = list.length - 1;
    }

    function stepItem(delta) {
        const list = currentList;
        var i = itemIndex + delta;
        if (i < 0) {
            if (groupIndex > 0) {
                groupIndex -= 1;
                itemIndex = Math.max(0, listOf(groupIndex).length - 1);
            }
            return;
        }
        if (i >= list.length) {
            if (groupIndex < groups.length - 1) {
                groupIndex += 1;
                itemIndex = 0;
            }
            return;
        }
        itemIndex = i;
    }

    onVisibleChanged: {
        if (visible) {
            groupIndex = 0;
            itemIndex = 0;
            inCatalog = false;
            keys.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: root.close()
        Keys.onTabPressed: root.inCatalog = !root.inCatalog
        Keys.onUpPressed: root.inCatalog ? root.catalogIndex = Math.max(0, root.catalogIndex - 1) : root.stepItem(-1)
        Keys.onDownPressed: root.inCatalog ? root.catalogIndex = Math.min(root.catalog.length - 1, root.catalogIndex + 1) : root.stepItem(1)
        Keys.onReturnPressed: if (root.inCatalog)
            root.addFromCatalog()
        Keys.onLeftPressed: event => {
            if (root.inCatalog)
                return;
            if (event.modifiers & Qt.ShiftModifier)
                root.moveToGroup(-1);
            else
                root.moveWithin(-1);
        }
        Keys.onRightPressed: event => {
            if (root.inCatalog)
                return;
            if (event.modifiers & Qt.ShiftModifier)
                root.moveToGroup(1);
            else
                root.moveWithin(1);
        }
        Keys.onPressed: event => {
            if (!root.inCatalog && (event.key === Qt.Key_X || event.key === Qt.Key_Delete)) {
                root.removeItem();
                event.accepted = true;
            }
        }

        OverlaySurface {
            preferredWidth: Theme.cellW * 76
            preferredHeight: Theme.overlayHeightLarge

            MouseArea {
                anchors.fill: parent
            }

            Flickable {
                id: leftScroll
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: hint.top
                anchors.margins: Theme.cellW
                anchors.bottomMargin: Theme.cellH * 2
                width: root.leftWidth
                clip: true
                contentWidth: width
                contentHeight: left.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: left

                    width: root.leftWidth
                    spacing: 0

                Line {
                    text: "MODULES"
                    color: root.inCatalog ? Theme.muted : Theme.fgDim
                    bottomPadding: Theme.cellH * 0.4
                }

                    Repeater {
                        model: root.groups

                    Column {
                        id: group

                        required property var modelData
                        required property int index

                        width: root.leftWidth
                        spacing: 0

                        Item {
                            width: group.width
                            height: Theme.controlHeight

                            Line {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: group.modelData.label
                                color: Theme.fgDim
                            }

                            // Leere Gruppe oder Ablage auf den Gruppenkopf:
                            // der Baustein kommt ans Ende dieser Gruppe.
                            DropArea {
                                anchors.fill: parent
                                enabled: root.dragGroup >= 0
                                onDropped: root.moveDragged(group.index, root.listOf(group.index).length)
                            }
                        }

                        Line {
                            visible: Config.value(group.modelData.key, []).length === 0
                            text: "     —"
                            color: Theme.muted
                        }

                        Repeater {
                            model: Config.value(group.modelData.key, [])

                            // Ausdruecklich `delegate:`. In der impliziten Form
                            // (Rectangle direkt als Kind) hat dieser Repeater
                            // nichts erzeugt -- ohne Fehler, ohne Meldung.
                            delegate: Rectangle {
                                id: row

                                required property var modelData
                                required property int index

                                readonly property bool current: !root.inCatalog && group.index === root.groupIndex && row.index === root.itemIndex

                                width: root.leftWidth
                                height: Theme.controlHeight
                                radius: Theme.radius
                                color: row.current ? Theme.selectedSurface(Theme.accent) : "transparent"

                                opacity: rowDrag.active ? 0.45 : 1
                                z: rowDrag.active ? 20 : 0

                                Drag.active: rowDrag.active
                                Drag.source: row
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                Line {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.cellW * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (row.current ? "◂ ▸ " : "    ") + Plugins.label(row.modelData)
                                    color: row.current ? Theme.selectedForeground(Theme.accent) : Theme.fg
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        root.inCatalog = false;
                                        root.groupIndex = group.index;
                                        root.itemIndex = row.index;
                                    }
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouseEvent => root.moveWithin(mouseEvent.button === Qt.RightButton ? -1 : 1)
                                }

                                DragHandler {
                                    id: rowDrag
                                    acceptedButtons: Qt.LeftButton
                                    target: null
                                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                                    onActiveChanged: {
                                        if (active) {
                                            root.inCatalog = false;
                                            root.dragGroup = group.index;
                                            root.dragIndex = row.index;
                                        } else if (root.dragGroup === group.index && root.dragIndex === row.index) {
                                            root.dragGroup = -1;
                                            root.dragIndex = -1;
                                        }
                                    }
                                }

                                // Obere Haelfte = davor, untere = dahinter.
                                DropArea {
                                    anchors.fill: parent
                                    enabled: root.dragGroup >= 0 && !(root.dragGroup === group.index && root.dragIndex === row.index)
                                    onDropped: drop => root.moveDragged(group.index, row.index + (drop.y > height / 2 ? 1 : 0))

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        height: Math.max(2, Theme.borderWidth * 2)
                                        color: Theme.accent
                                        visible: parent.containsDrag
                                    }
                                }
                            }
                        }
                    }
                    }
                }
            }

            Rectangle {
                anchors.right: leftScroll.right
                width: Theme.borderWidth * 2
                height: leftScroll.contentHeight > leftScroll.height
                    ? Math.max(Theme.cellH * 2, leftScroll.height * leftScroll.height / leftScroll.contentHeight)
                    : 0
                y: leftScroll.contentHeight > leftScroll.height
                    ? leftScroll.y + leftScroll.contentY * (leftScroll.height - height) / Math.max(1, leftScroll.contentHeight - leftScroll.height)
                    : leftScroll.y
                visible: height > 0
                color: Theme.muted
                z: 10
            }

            Flickable {
                id: rightScroll
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: hint.top
                anchors.margins: Theme.cellW
                anchors.bottomMargin: Theme.cellH * 2
                width: root.rightWidth
                clip: true
                contentWidth: width
                contentHeight: right.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: right

                    width: root.rightWidth
                    spacing: 0

                Line {
                    text: "AVAILABLE"
                    color: root.inCatalog ? Theme.fgDim : Theme.muted
                    bottomPadding: Theme.cellH * 0.4
                }

                    Repeater {
                        model: root.catalog

                    delegate: Rectangle {
                        id: catRow

                        required property var modelData
                        required property int index

                        readonly property bool current: root.inCatalog && catRow.index === root.catalogIndex

                        width: root.rightWidth
                        height: Theme.controlHeight
                        radius: Theme.radius
                        color: catRow.current ? Theme.selectedSurface(Theme.accent) : "transparent"

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            text: (catRow.current ? "▸ " : "  ") + Plugins.label(catRow.modelData) + (Plugins.source(catRow.modelData) === "" ? "" : "  ·plugin")
                            color: catRow.current ? Theme.selectedForeground(Theme.accent) : Theme.fgDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                root.inCatalog = true;
                                root.catalogIndex = catRow.index;
                            }
                            onClicked: root.addFromCatalog()
                        }
                    }
                    }
                }
            }

            Rectangle {
                anchors.right: rightScroll.right
                width: Theme.borderWidth * 2
                height: rightScroll.contentHeight > rightScroll.height
                    ? Math.max(Theme.cellH * 2, rightScroll.height * rightScroll.height / rightScroll.contentHeight)
                    : 0
                y: rightScroll.contentHeight > rightScroll.height
                    ? rightScroll.y + rightScroll.contentY * (rightScroll.height - height) / Math.max(1, rightScroll.contentHeight - rightScroll.height)
                    : rightScroll.y
                visible: height > 0
                color: Theme.muted
                z: 10
            }

            // Was der gewaehlte Baustein ueberhaupt tut. In der Liste steht
            // nur sein Name -- bei siebzehn Eintraegen ist das zu wenig.
            Line {
                anchors.bottom: hint.top
                anchors.left: parent.left
                anchors.margins: Theme.cellW
                anchors.bottomMargin: Theme.cellH * 0.3
                visible: root.inCatalog
                text: Plugins.describe(root.catalog[root.catalogIndex] ?? "")
                color: Theme.fgDim
            }

            Line {
                id: hint

                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: Theme.cellW
                text: "↑↓ select · ←→ move · Shift+←→ change group · x remove · Tab available · Enter add · Esc"
                color: Theme.muted
            }
        }
    }
}
