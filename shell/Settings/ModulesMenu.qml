import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

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
            "label": "Eingeklappt (Insel)"
        },
        {
            "key": "leftWidgets",
            "label": "Links"
        },
        {
            "key": "centerWidgets",
            "label": "Mitte"
        },
        {
            "key": "rightWidgets",
            "label": "Rechts"
        }
    ]

    readonly property var catalog: ["workspaces", "window", "clock", "media", "sys", "battery", "layout", "tray", "notifications", "clipboard", "capture", "control", "volume", "themes", "ai", "updates", "sep"]

    // Feste Breiten am Fenster statt `width: <Column>.width` an den Zeilen:
    // die Verweise vom Kind auf den Positionierer haben hier dazu gefuehrt,
    // dass die Zeilen gar nicht erst entstanden -- ohne Fehler, ohne Meldung.
    readonly property real leftWidth: Theme.cellW * 46
    readonly property real rightWidth: Theme.cellW * 24

    property int groupIndex: 0
    property int itemIndex: 0
    property bool inCatalog: false
    property int catalogIndex: 0

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

        Rectangle {
            anchors.centerIn: parent
            width: Theme.cellW * 76
            height: Math.max(left.implicitHeight, right.implicitHeight) + Theme.cellH * 3

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.accent

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: left

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.cellW
                width: root.leftWidth
                spacing: 0

                Text {
                    text: "BAUSTEINE"
                    color: root.inCatalog ? Theme.muted : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
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

                        Text {
                            text: group.modelData.label
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            topPadding: Theme.cellH * 0.3
                        }

                        Text {
                            visible: Config.value(group.modelData.key, []).length === 0
                            text: "     —"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
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
                                height: Theme.cellH * 1.3
                                radius: Theme.radius
                                color: row.current ? Theme.selection : "transparent"

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.cellW * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (row.current ? "◂ ▸ " : "    ") + row.modelData
                                    color: row.current ? Theme.readable(Theme.accent, Theme.selection) : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    renderType: Text.NativeRendering
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
                            }
                        }
                    }
                }
            }

            Column {
                id: right

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.cellW
                width: root.rightWidth
                spacing: 0

                Text {
                    text: "VORRAT"
                    color: root.inCatalog ? Theme.fgDim : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
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
                        height: Theme.cellH * 1.3
                        radius: Theme.radius
                        color: catRow.current ? Theme.selection : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW
                            anchors.verticalCenter: parent.verticalCenter
                            text: (catRow.current ? "▸ " : "  ") + catRow.modelData
                            color: catRow.current ? Theme.readable(Theme.accent, Theme.selection) : Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
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

            Text {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: Theme.cellW
                text: "↑↓ waehlen · ←→ verschieben · Shift+←→ in andere Gruppe · x entfernen · Tab Vorrat · Enter anhaengen · Esc"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }
        }
    }
}
