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

    readonly property real rowWidth: 32 * Theme.cellW

    spacing: 0

    QsMenuOpener {
        id: opener
        menu: root.handle
    }

    Repeater {
        model: opener.children

        Column {
            id: entryColumn

            required property var modelData

            property bool expanded: false

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
                visible: !entryColumn.modelData.isSeparator
                width: root.rowWidth
                height: visible ? Theme.rowHeight : 0
                radius: Theme.radius
                color: mouse.hovered && entryColumn.modelData.enabled ? Theme.hover : "transparent"

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
                        if (entryColumn.modelData.hasChildren) {
                            entryColumn.expanded = !entryColumn.expanded;
                            return;
                        }
                        entryColumn.modelData.triggered();
                        if (root.dismiss)
                            root.dismiss();
                    }
                }
            }

            Loader {
                active: entryColumn.expanded && entryColumn.modelData.hasChildren
                source: Qt.resolvedUrl("MenuView.qml")

                onLoaded: {
                    item.handle = entryColumn.modelData;
                    item.depth = root.depth + 1;
                    item.dismiss = root.dismiss;
                }
            }
        }
    }
}
