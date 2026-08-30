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
    readonly property real leftWidth: Theme.cellW * 62

    property int groupIndex: 0
    property int itemIndex: 0
    property bool inCatalog: false
    property int catalogIndex: 0
    property int dragGroup: -1
    property int dragIndex: -1

    readonly property var currentList: Config.value(groups[groupIndex].key, [])

    visible: true

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
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }

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

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity * 0.45 }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

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
            id: box
            dockedTop: true
            preferredWidth: Theme.cellW * 112
            preferredHeight: Theme.cellH * 38

            MouseArea { anchors.fill: parent }

            Column {
                id: content
                anchors.fill: parent
                anchors.margins: Theme.spaceXl
                spacing: Theme.spaceLg

                PanelHead {
                    id: head
                    rowWidth: content.width
                    icon: Icons.cp(0xF12E)
                    title: "Bar modules"
                    subtitle: "Arrange the island and bar · drag modules or use the keyboard"
                    badge: root.inCatalog ? "AVAILABLE" : root.groups[root.groupIndex].label.toUpperCase()
                    badgeColor: Theme.accent
                }

                Row {
                    id: panes
                    width: content.width
                    height: content.height - head.height - footer.height - content.spacing * 2
                    spacing: Theme.spaceXl

                    PanelSurface {
                        width: root.leftWidth
                        height: parent.height
                        raised: true
                        accentBorder: !root.inCatalog

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceSm
                            spacing: 0

                            SectionHeader {
                                width: parent.width
                                text: "Current layout"
                                detail: "4 groups"
                            }

                            Flickable {
                                id: leftScroll
                                width: parent.width
                                height: parent.height - Theme.controlHeight
                                contentWidth: width
                                contentHeight: left.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: left
                                    width: leftScroll.width
                                    spacing: Theme.spaceSm

                                    Repeater {
                                        model: root.groups

                                        Column {
                                            id: group
                                            required property var modelData
                                            required property int index
                                            width: left.width
                                            spacing: 0

                                            SectionHeader {
                                                width: parent.width
                                                text: group.modelData.label
                                                detail: root.listOf(group.index).length + " modules"

                                                DropArea {
                                                    anchors.fill: parent
                                                    enabled: root.dragGroup >= 0
                                                    onDropped: root.moveDragged(group.index, root.listOf(group.index).length)
                                                }
                                            }

                                            Line {
                                                visible: root.listOf(group.index).length === 0
                                                width: parent.width
                                                height: Theme.rowHeight
                                                leftPadding: Theme.spaceXl
                                                verticalAlignment: Text.AlignVCenter
                                                text: "No modules"
                                                color: Theme.muted
                                            }

                                            Repeater {
                                                model: Config.value(group.modelData.key, [])

                                                delegate: PanelRow {
                                                    id: moduleRow
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool current: !root.inCatalog
                                                        && group.index === root.groupIndex
                                                        && moduleRow.index === root.itemIndex

                                                    width: group.width
                                                    height: Theme.rowHeight
                                                    title: Plugins.label(moduleRow.modelData)
                                                    detail: Plugins.source(moduleRow.modelData) === "" ? "Built in" : "Plugin"
                                                    value: moduleRow.current ? "DRAG  ·  ← →" : ""
                                                    selected: moduleRow.current
                                                    visualFocus: moduleRow.current
                                                    interactive: true
                                                    opacity: moduleDrag.active ? 0.45 : 1
                                                    z: moduleDrag.active ? 20 : 0

                                                    Drag.active: moduleDrag.active
                                                    Drag.source: moduleRow
                                                    Drag.hotSpot.x: width / 2
                                                    Drag.hotSpot.y: height / 2

                                                    onTriggered: {
                                                        root.inCatalog = false;
                                                        root.groupIndex = group.index;
                                                        root.itemIndex = moduleRow.index;
                                                    }

                                                    DragHandler {
                                                        id: moduleDrag
                                                        acceptedButtons: Qt.LeftButton
                                                        target: null
                                                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                                                        onActiveChanged: {
                                                            if (active) {
                                                                root.inCatalog = false;
                                                                root.groupIndex = group.index;
                                                                root.itemIndex = moduleRow.index;
                                                                root.dragGroup = group.index;
                                                                root.dragIndex = moduleRow.index;
                                                            } else if (root.dragGroup === group.index && root.dragIndex === moduleRow.index) {
                                                                root.dragGroup = -1;
                                                                root.dragIndex = -1;
                                                            }
                                                        }
                                                    }

                                                    DropArea {
                                                        anchors.fill: parent
                                                        enabled: root.dragGroup >= 0
                                                            && !(root.dragGroup === group.index && root.dragIndex === moduleRow.index)
                                                        onDropped: drop => root.moveDragged(group.index, moduleRow.index + (drop.y > height / 2 ? 1 : 0))

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
                        }
                    }

                    PanelSurface {
                        width: panes.width - root.leftWidth - panes.spacing
                        height: parent.height
                        raised: false
                        accentBorder: root.inCatalog

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceSm
                            spacing: 0

                            SectionHeader {
                                width: parent.width
                                text: "Available"
                                detail: root.catalog.length + " modules"
                            }

                            Flickable {
                                id: rightScroll
                                width: parent.width
                                height: parent.height - Theme.controlHeight
                                contentWidth: width
                                contentHeight: available.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: available
                                    width: rightScroll.width
                                    spacing: 0

                                    Repeater {
                                        model: root.catalog

                                        PanelRow {
                                            id: catalogRow
                                            required property var modelData
                                            required property int index
                                            readonly property bool current: root.inCatalog && catalogRow.index === root.catalogIndex

                                            width: available.width
                                            height: Theme.rowHeight
                                            title: Plugins.label(catalogRow.modelData)
                                            detail: Plugins.describe(catalogRow.modelData)
                                            value: catalogRow.current ? "ENTER  ·  ADD" : "ADD"
                                            selected: catalogRow.current
                                            visualFocus: catalogRow.current
                                            interactive: true
                                            onTriggered: {
                                                root.inCatalog = true;
                                                root.catalogIndex = catalogRow.index;
                                                root.addFromCatalog();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    id: footer
                    width: content.width
                    height: Theme.controlHeight
                    spacing: Theme.spaceMd

                    Line {
                        width: parent.width - closeButton.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Tab switches pane  ·  ↑↓ selects  ·  ←→ reorders  ·  Shift+←→ changes group  ·  Delete removes"
                        color: Theme.muted
                        elide: Text.ElideRight
                    }

                    ActionButton {
                        id: closeButton
                        text: "Close"
                        compact: true
                        onTriggered: root.close()
                    }
                }
            }
        }
    }
}
