import QtQuick
import Quickshell
import qs.Common

// Ein DBus-Menue als Liste, wie sie ein Terminalprogramm zeichnen wuerde.
//
// Untermenues klappen an Ort und Stelle auf, statt seitlich herauszufahren:
// eingerueckt, mit einem Pfeil davor. Das spart ein zweites Fenster und passt
// besser zu einer Oberflaeche, die sonst auch nur Zeilen kennt.
//
// Die Verschachtelung laedt diese Datei ueber ihren Pfad nach. Sich selbst
// direkt zu verwenden geht in QML nicht -- der Typ waere waehrend seiner
// eigenen Definition noch nicht fertig.
Column {
    id: root

    property var handle: null
    property int depth: 0
    // Kein Name, der mit "on" beginnt: QML liest so etwas als Signalhandler.
    property var dismiss: null
    property var back: null

    readonly property real rowWidth: 32 * Theme.cellW
    readonly property Item initialFocusItem: firstFocusableItem()

    spacing: 0

    function firstFocusableItem() {
        for (var i = 0; i < entries.count; i++) {
            const item = entries.itemAt(i);
            if (item?.focusItem?.visible && item.focusItem.enabled)
                return item.focusItem;
        }
        return null;
    }

    function moveFocus(item, forward) {
        const next = item.nextItemInFocusChain(forward);
        if (next && next !== item)
            next.forceActiveFocus(Qt.TabFocusReason);
    }

    QsMenuOpener {
        id: opener
        menu: root.handle
    }

    Repeater {
        id: entries
        model: opener.children

        Column {
            id: entryColumn

            required property var modelData

            property bool expanded: false
            property alias focusItem: menuRow

            spacing: 0

            // Trenner: eine Linie ueber die volle Breite.
            Rectangle {
                visible: entryColumn.modelData.isSeparator
                width: root.rowWidth
                height: visible ? Theme.cellH * 0.8 : 0
                color: "transparent"

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: Theme.borderWidth
                    color: Theme.muted
                }
            }

            Rectangle {
                id: menuRow
                visible: !entryColumn.modelData.isSeparator
                width: root.rowWidth
                height: visible ? Theme.rowHeight : 0
                radius: Theme.radius
                color: mouse.hovered && entryColumn.modelData.enabled ? Theme.hover : "transparent"
                border.width: activeFocus ? Theme.borderWidth : 0
                border.color: Theme.focusBorder
                activeFocusOnTab: visible && entryColumn.modelData.enabled
                Accessible.role: Accessible.MenuItem
                Accessible.name: entryColumn.modelData.text || "Menu item"
                Accessible.description: entryColumn.modelData.hasChildren ? "Opens submenu" : "Activates menu action"
                Accessible.focusable: activeFocusOnTab
                Accessible.focused: activeFocus
                Accessible.onPressAction: menuRow.activate()

                function activate() {
                    if (!entryColumn.modelData.enabled)
                        return;
                    if (entryColumn.modelData.hasChildren) {
                        entryColumn.expanded = !entryColumn.expanded;
                        if (entryColumn.expanded)
                            Qt.callLater(function() {
                                submenu.item?.initialFocusItem?.forceActiveFocus(Qt.TabFocusReason);
                            });
                        return;
                    }
                    entryColumn.modelData.triggered();
                    if (root.dismiss)
                        root.dismiss();
                }

                Keys.onReturnPressed: event => { menuRow.activate(); event.accepted = true; }
                Keys.onEnterPressed: event => { menuRow.activate(); event.accepted = true; }
                Keys.onSpacePressed: event => { menuRow.activate(); event.accepted = true; }
                Keys.onRightPressed: event => { menuRow.activate(); event.accepted = true; }
                Keys.onLeftPressed: event => {
                    if (root.back) root.back();
                    else if (entryColumn.expanded) entryColumn.expanded = false;
                    event.accepted = true;
                }
                Keys.onUpPressed: event => { root.moveFocus(menuRow, false); event.accepted = true; }
                Keys.onDownPressed: event => { root.moveFocus(menuRow, true); event.accepted = true; }

                Line {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.cellW / 2 + root.depth * Theme.cellW * 2
                    anchors.verticalCenter: parent.verticalCenter

                    text: {
                        const e = entryColumn.modelData;
                        var prefix = "";
                        if (e.buttonType === QsMenuButtonType.CheckBox)
                            prefix = e.checkState === Qt.Checked ? Icons.check + "  " : Icons.circleOutline + "  ";
                        else if (e.buttonType === QsMenuButtonType.RadioButton)
                            prefix = e.checkState === Qt.Checked ? "●  " : "○  ";
                        const suffix = e.hasChildren ? (entryColumn.expanded ? "  ▾" : "  ▸") : "";
                        return prefix + e.text + suffix;
                    }
                    color: !entryColumn.modelData.enabled ? Theme.muted : Theme.fg
                    font.pixelSize: Theme.fontBody
                    elide: Text.ElideRight
                }

                HoverHandler {
                    id: mouse

                    enabled: entryColumn.modelData.enabled
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: entryColumn.modelData.enabled

                    onTapped: {
                        menuRow.forceActiveFocus(Qt.MouseFocusReason);
                        menuRow.activate();
                    }
                }
            }

            Loader {
                id: submenu
                active: entryColumn.expanded && entryColumn.modelData.hasChildren
                source: Qt.resolvedUrl("MenuView.qml")

                onLoaded: {
                    item.handle = entryColumn.modelData;
                    item.depth = root.depth + 1;
                    item.dismiss = root.dismiss;
                    item.back = () => {
                        entryColumn.expanded = false;
                        menuRow.forceActiveFocus(Qt.BacktabFocusReason);
                    };
                }
            }
        }
    }
}
