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
    property int dropGroup: -1
    property int dropIndex: -1

    readonly property var currentList: configuredList(groups[groupIndex].key)

    visible: true

    screen: Compositor.focusedScreen
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

    function configuredList(key) {
        if (key === "collapsedWidgets") return Config.collapsedWidgets;
        if (key === "leftWidgets") return Config.leftWidgets;
        if (key === "centerWidgets") return Config.centerWidgets;
        if (key === "rightWidgets") return Config.rightWidgets;
        return [];
    }

    function listOf(i) {
        // Use the same public defaults as the live bar. Reading a missing key
        // as [] made the editor claim that default-backed groups were empty.
        return configuredList(groups[i].key).slice();
    }

    function save(i, list) {
        Config.set(groups[i].key, list);
    }

    function saveMove(fromGroup, from, toGroup, to) {
        const changes = {};
        changes[groups[fromGroup].key] = from;
        changes[groups[toGroup].key] = to;
        Config.setValues(changes);
    }

    function placements(id) {
        const result = [];
        for (var i = 0; i < groups.length; i++) {
            if (listOf(i).indexOf(id) >= 0)
                result.push(groups[i].label);
        }
        return result.join(" · ");
    }

    function placementStatus(id) {
        if (Config.mode === "bar" || Config.mode === "pill") {
            for (var i = 1; i < groups.length; i++) {
                if (listOf(i).indexOf(id) >= 0)
                    return "IN BAR";
            }
            return listOf(0).indexOf(id) >= 0 ? "ISLAND" : "ADD";
        }
        return placements(id) !== "" ? "IN BAR" : "ADD";
    }

    function selectConfigured(id) {
        const start = (Config.mode === "bar" || Config.mode === "pill") ? 1 : 0;
        for (var i = start; i < groups.length; i++) {
            const index = listOf(i).indexOf(id);
            if (index < 0)
                continue;
            groupIndex = i;
            itemIndex = index;
            inCatalog = false;
            return true;
        }
        return false;
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
        const to = listOf(target);
        to.push(item);
        saveMove(groupIndex, from, target, to);
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
            const to = listOf(toGroup);
            const target = Math.max(0, Math.min(toIndex, to.length));
            to.splice(target, 0, item);
            saveMove(fromGroup, from, toGroup, to);
            groupIndex = toGroup;
            itemIndex = target;
        }
        inCatalog = false;
        dragGroup = -1;
        dragIndex = -1;
    }

    function addFromCatalog() {
        const list = listOf(groupIndex);
        const item = catalog[catalogIndex];
        const existing = item === "sep" ? -1 : list.indexOf(item);
        if (existing >= 0) {
            itemIndex = existing;
            inCatalog = false;
            return;
        }
        list.push(item);
        save(groupIndex, list);
        itemIndex = list.length - 1;
    }

    function activateCatalog() {
        const item = catalog[catalogIndex];
        if (!selectConfigured(item))
            addFromCatalog();
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
            // The collapsed list is not rendered in bar/pill mode. Start in
            // the left group so adding a module cannot silently put it into a
            // hidden island-only layout.
            groupIndex = (Config.mode === "bar" || Config.mode === "pill") ? 1 : 0;
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
            root.activateCatalog()
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
                    subtitle: "Arrange here or Mod-drag modules directly on the bar"
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
                                contentHeight: left.height
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: left
                                    width: root.leftWidth - Theme.spaceSm * 2
                                    height: childrenRect.height
                                    spacing: Theme.spaceSm

                                    Repeater {
                                        model: root.groups

                                        Column {
                                            id: group
                                            required property var modelData
                                            required property int index
                                            readonly property var widgets: group.modelData.key === "collapsedWidgets" ? Config.collapsedWidgets
                                                : (group.modelData.key === "leftWidgets" ? Config.leftWidgets
                                                : (group.modelData.key === "centerWidgets" ? Config.centerWidgets : Config.rightWidgets))
                                            width: root.leftWidth - Theme.spaceSm * 2
                                            height: childrenRect.height
                                            spacing: 0

                                            SectionHeader {
                                                width: parent.width
                                                text: group.modelData.label
                                                detail: group.widgets.length + " modules"

                                                DropArea {
                                                    anchors.fill: parent
                                                    enabled: root.dragGroup >= 0
                                                    onEntered: drag => {
                                                        root.dropGroup = group.index;
                                                        root.dropIndex = root.listOf(group.index).length;
                                                        drag.acceptProposedAction();
                                                    }
                                                    onExited: {
                                                        if (root.dropGroup === group.index
                                                                && root.dropIndex === root.listOf(group.index).length) {
                                                            root.dropGroup = -1;
                                                            root.dropIndex = -1;
                                                        }
                                                    }
                                                }
                                            }

                                            Line {
                                                visible: group.widgets.length === 0
                                                width: parent.width
                                                height: Theme.rowHeight
                                                leftPadding: Theme.spaceXl
                                                verticalAlignment: Text.AlignVCenter
                                                text: "No modules"
                                                color: Theme.muted
                                            }

                                            Repeater {
                                                model: group.widgets

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

                                                    onTriggered: {
                                                        root.inCatalog = false;
                                                        root.groupIndex = group.index;
                                                        root.itemIndex = moduleRow.index;
                                                    }

                                                    Item {
                                                        id: menuDragProxy
                                                        z: 100
                                                        width: moduleRow.width
                                                        height: moduleRow.height
                                                        Drag.source: moduleRow
                                                        Drag.hotSpot.x: width / 2
                                                        Drag.hotSpot.y: height / 2

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            visible: moduleDrag.active
                                                            color: Theme.controlFill(true, false, false)
                                                            border.width: Theme.borderWidth
                                                            border.color: Theme.focusBorder
                                                            radius: Theme.radius

                                                            Line {
                                                                anchors.centerIn: parent
                                                                text: Plugins.label(moduleRow.modelData)
                                                                color: Theme.text
                                                            }
                                                        }
                                                    }

                                                    DragHandler {
                                                        id: moduleDrag
                                                        acceptedButtons: Qt.LeftButton
                                                        target: menuDragProxy
                                                        onActiveChanged: {
                                                            if (active) {
                                                                root.inCatalog = false;
                                                                root.groupIndex = group.index;
                                                                root.itemIndex = moduleRow.index;
                                                                root.dragGroup = group.index;
                                                                root.dragIndex = moduleRow.index;
                                                                root.dropGroup = -1;
                                                                root.dropIndex = -1;
                                                                menuDragProxy.Drag.active = true;
                                                            } else if (root.dragGroup === group.index && root.dragIndex === moduleRow.index) {
                                                                const targetGroup = root.dropGroup;
                                                                const targetIndex = root.dropIndex;
                                                                menuDragProxy.Drag.cancel();
                                                                menuDragProxy.x = 0;
                                                                menuDragProxy.y = 0;
                                                                if (targetGroup >= 0) {
                                                                    Qt.callLater(() => root.moveDragged(targetGroup, targetIndex));
                                                                } else {
                                                                    root.dragGroup = -1;
                                                                    root.dragIndex = -1;
                                                                }
                                                                root.dropGroup = -1;
                                                                root.dropIndex = -1;
                                                            }
                                                        }
                                                    }

                                                    DropArea {
                                                        anchors.fill: parent
                                                        enabled: root.dragGroup >= 0
                                                            && !(root.dragGroup === group.index && root.dragIndex === moduleRow.index)
                                                        onEntered: drag => {
                                                            root.dropGroup = group.index;
                                                            root.dropIndex = moduleRow.index + (drag.y > height / 2 ? 1 : 0);
                                                            drag.acceptProposedAction();
                                                        }
                                                        onPositionChanged: drag => {
                                                            root.dropGroup = group.index;
                                                            root.dropIndex = moduleRow.index + (drag.y > height / 2 ? 1 : 0);
                                                        }
                                                        onExited: {
                                                            if (root.dropGroup === group.index) {
                                                                root.dropGroup = -1;
                                                                root.dropIndex = -1;
                                                            }
                                                        }

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
                                contentHeight: available.height
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: available
                                    width: rightScroll.width
                                    height: childrenRect.height
                                    spacing: 0

                                    Repeater {
                                        model: root.catalog

                                        PanelRow {
                                            id: catalogRow
                                            required property var modelData
                                            required property int index
                                            readonly property bool current: root.inCatalog && catalogRow.index === root.catalogIndex
                                            readonly property string placement: root.placements(catalogRow.modelData)
                                            readonly property string placementState: root.placementStatus(catalogRow.modelData)

                                            width: available.width
                                            height: Theme.rowHeight
                                            title: Plugins.label(catalogRow.modelData)
                                            detail: placement !== "" ? "Placed: " + placement : Plugins.describe(catalogRow.modelData)
                                            value: placementState === "ADD" && catalogRow.current ? "ENTER  ·  ADD" : placementState
                                            selected: catalogRow.current
                                            visualFocus: catalogRow.current
                                            interactive: true
                                            onTriggered: {
                                                root.inCatalog = true;
                                                root.catalogIndex = catalogRow.index;
                                                root.activateCatalog();
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
