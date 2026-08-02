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
                height: visible ? Theme.cellH * 1.4 : 0
                radius: Theme.radius
                color: mouse.containsMouse && entryColumn.modelData.enabled ? Theme.selection : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.cellW / 2 + root.depth * Theme.cellW * 2
                    anchors.verticalCenter: parent.verticalCenter

                    // Kaestchen und Punkte wie in einer TUI: [x] fuer Haken,
                    // (•) fuer eine Auswahl, sonst zwei Leerzeichen, damit die
                    // Beschriftungen untereinander stehen.
                    text: {
                        const e = entryColumn.modelData;
                        var prefix = "";
                        if (e.buttonType === QsMenuButtonType.CheckBox)
                            prefix = e.checkState === Qt.Checked ? "[x] " : "[ ] ";
                        else if (e.buttonType === QsMenuButtonType.RadioButton)
                            prefix = e.checkState === Qt.Checked ? "(•) " : "( ) ";
                        const suffix = e.hasChildren ? (entryColumn.expanded ? "  ▾" : "  ▸") : "";
                        return prefix + e.text + suffix;
                    }
                    color: entryColumn.modelData.enabled ? Theme.fg : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: entryColumn.modelData.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
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
