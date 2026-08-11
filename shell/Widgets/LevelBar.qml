import QtQuick
import qs.Common

// Ein Balken aus Bloecken, wie ihn ein Terminalprogramm zeichnen wuerde.
//
// Keine Fortschrittsleiste mit abgerundeten Ecken, sondern `cells` Zeichen
// nebeneinander: gefuellt bis zum Wert, danach gedaempft. Ziehen und Klicken
// setzt den Wert -- so lange die Maus gedrueckt ist, folgt er ihr.
Item {
    id: root

    property int value: 0
    property int maximum: 100
    property int cells: 20
    property color fillColor: Theme.accent
    property bool interactive: true

    signal moved(int value)

    readonly property int filled: Math.round(cells * Math.max(0, Math.min(maximum, value)) / maximum)

    implicitWidth: cells * Theme.cellW
    implicitHeight: Theme.cellH

    Line {
        id: text

        anchors.fill: parent
        // Ein Zeichen je Zelle. Zwei Textstuecke uebereinander waeren
        // aufwaendiger als eines mit Auszeichnung.
        text: "<font color=\"" + root.fillColor + "\">" + "█".repeat(root.filled) + "</font>" + "<font color=\"" + Theme.muted + "\">" + "░".repeat(Math.max(0, root.cells - root.filled)) + "</font>"
        textFormat: Text.RichText
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton

        function apply(x) {
            const share = Math.max(0, Math.min(1, x / root.width));
            root.moved(Math.round(share * root.maximum));
        }

        onPressed: mouseEvent => apply(mouseEvent.x)
        onPositionChanged: mouseEvent => {
            if (pressed)
                apply(mouseEvent.x);
        }
        onWheel: wheelEvent => root.moved(root.value + (wheelEvent.angleDelta.y > 0 ? 5 : -5))
    }
}
