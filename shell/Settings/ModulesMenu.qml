import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Widgets/FocusScroll.js" as FocusScroll

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
    readonly property real leftWidth: Math.min(Theme.cellW * 62, (box.width - Theme.spaceXl * 3) * 0.55)

    property int groupIndex: 0
    property int itemIndex: 0
    property bool inCatalog: false
    property bool footerFocused: false
    property int catalogIndex: 0
    property int dragGroup: -1
    property int dragIndex: -1
    property int dropGroup: -1
    property int dropIndex: -1
    property bool closing: false

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
        closing = true;
        Runtime.modulesOpen = false;
    }
    function requestClose(done) { closing = true; box.dismiss(done); }
    function requestOpen() { closing = false; box.enter(); Qt.callLater(root.syncFocus); }

    function syncFocus() {
        if (!root.visible || root.closing || root.dragGroup >= 0)
            return;
        const group = groupRows.itemAt(root.groupIndex);
        const row = root.footerFocused ? closeButton : root.inCatalog ? catalogRows.itemAt(root.catalogIndex)
            : (group ? group.rowAt(root.itemIndex) : null);
        (row || keys).forceActiveFocus();
        if (row && row !== closeButton)
            revealFocusedItem(row, root.inCatalog ? rightScroll : leftScroll);
    }

    function revealFocusedItem(item, viewport) {
        const mapped = item.mapToItem(viewport.contentItem, 0, 0);
        // Keep the group heading in view when selecting its first placement.
        const margin = viewport === leftScroll && root.itemIndex === 0
            ? Theme.controlHeight + Theme.spaceSm : Theme.spaceSm;
        viewport.contentY = FocusScroll.contentYForFocus(mapped.y, item.height,
            viewport.contentY, viewport.height, viewport.contentHeight, margin);
    }

    onFooterFocusedChanged: Qt.callLater(root.syncFocus)
    onGroupIndexChanged: Qt.callLater(root.syncFocus)
    onItemIndexChanged: Qt.callLater(root.syncFocus)
    onInCatalogChanged: Qt.callLater(root.syncFocus)
    onCatalogIndexChanged: Qt.callLater(root.syncFocus)
    onCurrentListChanged: Qt.callLater(root.syncFocus)
    onCatalogChanged: Qt.callLater(root.syncFocus)
    onDragGroupChanged: if (dragGroup < 0) Qt.callLater(root.syncFocus)
    Component.onCompleted: Qt.callLater(root.syncFocus)

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
        return Config.set(groups[i].key, list);
    }

    function saveMove(fromGroup, from, toGroup, to) {
        const changes = {};
        changes[groups[fromGroup].key] = from;
        changes[groups[toGroup].key] = to;
        return Config.setValues(changes);
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
        if (!Config.configValid || root.closing) return;
        const list = listOf(groupIndex);
        const target = itemIndex + delta;
        if (target < 0 || target >= list.length)
            return;
        const item = list.splice(itemIndex, 1)[0];
        list.splice(target, 0, item);
        if (!save(groupIndex, list)) return;
        itemIndex = target;
    }

    // In die Nachbargruppe schieben -- ans Ende, dort faellt es auf.
    function moveToGroup(delta) {
        if (!Config.configValid || root.closing) return;
        const from = listOf(groupIndex);
        if (itemIndex >= from.length)
            return;
        const target = groupIndex + delta;
        if (target < 0 || target >= groups.length)
            return;
        const item = from.splice(itemIndex, 1)[0];
        const to = listOf(target);
        to.push(item);
        if (!saveMove(groupIndex, from, target, to)) return;
        groupIndex = target;
        itemIndex = to.length - 1;
    }

    function removeItem() {
        if (!Config.configValid || root.closing) return;
        const list = listOf(groupIndex);
        if (itemIndex >= list.length)
            return;
        list.splice(itemIndex, 1);
        if (!save(groupIndex, list)) return;
        itemIndex = Math.max(0, Math.min(itemIndex, list.length - 1));
    }

    function moveDragged(toGroup, toIndex) {
        if (!Config.configValid || root.closing) return;
        if (dragGroup < 0 || dragIndex < 0 || toGroup < 0 || toGroup >= groups.length)
            return;
        const fromGroup = dragGroup;
        const fromIndex = dragIndex;
        const from = listOf(fromGroup);
        if (fromIndex >= from.length)
            return;
        const item = from.splice(fromIndex, 1)[0];
        if (fromGroup === toGroup) {
            const adjusted = Math.max(0, Math.min(toIndex - (fromIndex < toIndex ? 1 : 0), from.length));
            from.splice(adjusted, 0, item);
            if (save(fromGroup, from)) {
                groupIndex = fromGroup;
                itemIndex = adjusted;
            }
        } else {
            const to = listOf(toGroup);
            const target = Math.max(0, Math.min(toIndex, to.length));
            to.splice(target, 0, item);
            if (saveMove(fromGroup, from, toGroup, to)) {
                groupIndex = toGroup;
                itemIndex = target;
            }
        }
        inCatalog = false;
        dragGroup = -1;
        dragIndex = -1;
    }

    function addFromCatalog() {
        if (!Config.configValid || root.closing) return;
        const list = listOf(groupIndex);
        const item = catalog[catalogIndex];
        if (item === undefined)
            return;
        const existing = item === "sep" ? -1 : list.indexOf(item);
        if (existing >= 0) {
            itemIndex = existing;
            inCatalog = false;
            return;
        }
        list.push(item);
        if (!save(groupIndex, list)) return;
        itemIndex = list.length - 1;
    }

    function activateCatalog() {
        const item = catalog[catalogIndex];
        if (item === undefined)
            return;
        if (item === "sep" || !selectConfigured(item))
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

    function switchPane(direction = 1) {
        const order = root.catalog.length ? [0, 1, 2] : [0, 2];
        const current = root.footerFocused ? 2 : root.inCatalog ? 1 : 0;
        const next = order[(order.indexOf(current) + direction + order.length) % order.length];
        root.footerFocused = next === 2;
        root.inCatalog = next === 1;
        Qt.callLater(root.syncFocus);
    }

    onVisibleChanged: {
        if (visible) {
            closing = false;
            // The collapsed list is not rendered in bar/pill mode. Start in
            // the left group so adding a module cannot silently put it into a
            // hidden island-only layout.
            groupIndex = (Config.mode === "bar" || Config.mode === "pill") ? 1 : 0;
            itemIndex = 0;
            inCatalog = false;
            Qt.callLater(root.syncFocus);
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: root.close()
        Keys.onTabPressed: root.switchPane()
        Keys.onBacktabPressed: root.switchPane(-1)
        Keys.onUpPressed: if (!root.footerFocused) root.inCatalog ? root.catalogIndex = Math.max(0, root.catalogIndex - 1) : root.stepItem(-1)
        Keys.onDownPressed: if (!root.footerFocused) root.inCatalog ? root.catalogIndex = Math.min(root.catalog.length - 1, root.catalogIndex + 1) : root.stepItem(1)

        Keys.onLeftPressed: event => {
            if (root.inCatalog || root.footerFocused)
                return;
            if (event.modifiers & Qt.ShiftModifier)
                root.moveToGroup(-1);
            else
                root.moveWithin(-1);
        }
        Keys.onRightPressed: event => {
            if (root.inCatalog || root.footerFocused)
                return;
            if (event.modifiers & Qt.ShiftModifier)
                root.moveToGroup(1);
            else
                root.moveWithin(1);
        }
        Keys.onPressed: event => {
            if (!root.inCatalog && !root.footerFocused && (event.key === Qt.Key_X || event.key === Qt.Key_Delete)) {
                root.removeItem();
                event.accepted = true;
            }
        }

        OverlaySurface {
            id: box
            dockedTop: true
            preferredWidth: Theme.cellW * 112
            preferredHeight: Theme.cellH * 38
            motionEnabled: false
            color: Theme.bg
            border.color: Theme.panelBorder

            MouseArea { anchors.fill: parent }

            Column {
                id: content
                anchors.fill: parent
                anchors.margins: Theme.spaceXl
                spacing: Theme.spaceLg

                Column {
                    id: head
                    width: parent.width
                    spacing: Theme.spaceXs
                    PanelHead { rowWidth: parent.width; title: "Bar modules" }
                    Line {
                        width: parent.width
                        text: "Arrange here or Mod-drag modules directly on the bar"
                        font.pixelSize: Theme.fontCaption
                        color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
                        elide: Text.ElideRight
                    }
                }
                Line {
                    id: errors
                    width: parent.width
                    visible: Config.readError !== "" || Config.writeError !== ""
                    text: [Config.readError, Config.writeError].filter(e => e !== "").join("\n")
                    color: Theme.readable(Theme.red, Theme.bg, 4.5)
                    wrapMode: Text.Wrap
                }

                Row {
                    id: panes
                    width: content.width
                    height: Math.max(Theme.rowHeight, content.height - head.height - footer.height
                        - content.spacing * (errors.visible ? 3 : 2) - (errors.visible ? errors.height : 0))
                    spacing: Theme.spaceXl

                    PanelSurface {
                        width: root.leftWidth
                        height: parent.height
                        color: "transparent"
                        border.width: 0

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
                                onContentHeightChanged: Qt.callLater(root.syncFocus)
                                onHeightChanged: Qt.callLater(root.syncFocus)
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                Column {
                                    id: left
                                    width: root.leftWidth - Theme.spaceSm * 3
                                    height: childrenRect.height
                                    spacing: Theme.spaceSm

                                    Repeater {
                                        id: groupRows
                                        model: root.groups
                                        onItemAdded: Qt.callLater(root.syncFocus)

                                        Column {
                                            id: group
                                            required property var modelData
                                            required property int index
                                            function rowAt(index) { return group.widgets.length ? moduleRows.itemAt(index) : emptyRow; }
                                            readonly property var widgets: group.modelData.key === "collapsedWidgets" ? Config.collapsedWidgets
                                                : (group.modelData.key === "leftWidgets" ? Config.leftWidgets
                                                : (group.modelData.key === "centerWidgets" ? Config.centerWidgets : Config.rightWidgets))
                                            width: root.leftWidth - Theme.spaceSm * 3
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

                                            PanelRow {
                                                id: emptyRow
                                                visible: group.widgets.length === 0
                                                width: parent.width
                                                height: Math.max(Theme.rowHeight, Theme.cellH * 2 + Theme.spaceSm)
                                                title: "No modules"
                                                detail: "Select from Available to add"
                                                interactive: true
                                                accessibleSelected: !root.inCatalog && !root.footerFocused && root.groupIndex === group.index
                                                color: activeFocus || hovered ? Theme.mix(Theme.bg, Theme.fg, 0.08) : "transparent"
                                                border.width: activeFocus ? Theme.borderWidth : 0
                                                Keys.forwardTo: [keys]
                                                onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(emptyRow, leftScroll)
                                                onTriggered: {
                                                    root.groupIndex = group.index;
                                                    root.itemIndex = 0;
                                                    root.footerFocused = false;
                                                    root.inCatalog = root.catalog.length > 0;
                                                    Qt.callLater(root.syncFocus);
                                                }
                                            }

                                            Repeater {
                                                id: moduleRows
                                                model: group.widgets
                                                onItemAdded: Qt.callLater(root.syncFocus)
                                                onItemRemoved: Qt.callLater(root.syncFocus)

                                                delegate: PanelRow {
                                                    id: moduleRow
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool current: !root.inCatalog && !root.footerFocused
                                                        && group.index === root.groupIndex
                                                        && moduleRow.index === root.itemIndex

                                                    width: group.width
                                                    height: Math.max(Theme.rowHeight, Theme.cellH * 2 + Theme.spaceSm)
                                                    title: Plugins.label(moduleRow.modelData)
                                                    detail: Plugins.source(moduleRow.modelData) === "" ? "Built in" : "Plugin"
                                                    value: moduleRow.current ? "↔" : ""
                                                    accessibleSelected: moduleRow.current
                                                    color: moduleRow.current || hovered ? Theme.mix(Theme.bg, Theme.fg, 0.08) : "transparent"
                                                    border.width: activeFocus ? Theme.borderWidth : 0
                                                    visualFocus: activeFocus
                                                    interactive: true
                                                    Keys.forwardTo: [keys]
                                                    onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(moduleRow, leftScroll)
                                                    opacity: moduleDrag.active ? 0.45 : 1
                                                    z: moduleDrag.active ? 20 : 0

                                                    onTriggered: {
                                                        root.footerFocused = false;
                                                        root.inCatalog = false;
                                                        root.groupIndex = group.index;
                                                        root.itemIndex = moduleRow.index;
                                                        Qt.callLater(root.syncFocus);
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
                                                        enabled: Config.configValid
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
                        color: "transparent"
                        border.width: 0

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
                                onContentHeightChanged: Qt.callLater(root.syncFocus)
                                onHeightChanged: Qt.callLater(root.syncFocus)
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                Column {
                                    id: available
                                    width: Math.max(0, rightScroll.width - Theme.spaceSm)
                                    height: childrenRect.height
                                    spacing: 0

                                    Line {
                                        visible: root.catalog.length === 0
                                        width: parent.width
                                        text: "No available modules"
                                        color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
                                        wrapMode: Text.Wrap
                                    }
                                    Repeater {
                                        id: catalogRows
                                        model: root.catalog
                                        onItemAdded: Qt.callLater(root.syncFocus)
                                        onItemRemoved: Qt.callLater(root.syncFocus)

                                        PanelRow {
                                            id: catalogRow
                                            required property var modelData
                                            required property int index
                                            readonly property bool current: root.inCatalog && !root.footerFocused && catalogRow.index === root.catalogIndex
                                            readonly property string placement: root.placements(catalogRow.modelData)
                                            readonly property string placementState: root.placementStatus(catalogRow.modelData)

                                            width: available.width
                                            height: Math.max(Theme.rowHeight, Theme.cellH * 2 + Theme.spaceSm)
                                            title: Plugins.label(catalogRow.modelData)
                                            detail: placement !== "" ? "Placed: " + placement : Plugins.describe(catalogRow.modelData)
                                            value: placementState
                                            accessibleSelected: catalogRow.current
                                            color: catalogRow.current || hovered ? Theme.mix(Theme.bg, Theme.fg, 0.08) : "transparent"
                                            border.width: activeFocus ? Theme.borderWidth : 0
                                            visualFocus: activeFocus
                                            interactive: true
                                            Keys.forwardTo: [keys]
                                            onActiveFocusChanged: if (activeFocus) root.revealFocusedItem(catalogRow, rightScroll)
                                            onTriggered: {
                                                root.footerFocused = false;
                                                root.inCatalog = true;
                                                root.catalogIndex = catalogRow.index;
                                                root.activateCatalog();
                                                Qt.callLater(root.syncFocus);
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
                    height: Math.max(Theme.controlHeight, shortcutHelp.implicitHeight)
                    spacing: Theme.spaceMd

                    Line {
                        id: shortcutHelp
                        width: parent.width - closeButton.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Tab: layout / available / close  ·  ↑↓ select  ·  ←→ reorder  ·  Shift+←→ move group  ·  Enter add/select  ·  Delete remove"
                        font.pixelSize: Theme.fontCaption
                        color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
                        wrapMode: Text.WordWrap
                    }

                    ActionButton {
                        id: closeButton
                        text: "Close"
                        compact: true
                        Keys.forwardTo: [keys]
                        onActiveFocusChanged: if (activeFocus) root.footerFocused = true
                        onTriggered: root.close()
                    }
                }
            }
        }
    }
}
