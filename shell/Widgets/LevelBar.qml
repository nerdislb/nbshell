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

    // So breit, wie die Bloecke WIRKLICH gemalt werden -- nicht `cells *
    // cellW`.
    //
    // An diesem Unterschied ging eine Zeile kaputt: `cellW` ist die
    // Vorschubbreite der Ziffer 0 (6,5 px), die Bloecke legt Qt aber mit rund
    // 7 px je Zeichen um. Bei 24 Zellen sind das 168 statt 156 -- knapp zwei
    // Zeichen, die ueber den eigenen Kasten hinausragen, waehrend der Nachbar
    // in der Reihe brav nach 156 px gesetzt wird und dann unter dem Balkenende
    // liegt. Auch die Tinte des Vollblocks ist breiter als sein Vorschub
    // (gerendert 7 px bei 6,5 px Vorschub), es liegt also nicht bloss an der
    // Rundung der Zeichensatzdarstellung.
    //
    // Gesehen hat man es nur am Mikrofon: dessen Balken steht meist auf 100 %,
    // und ein voller Balken ist sichtbar, ein leerer nicht.
    //
    // Nachgemessen statt vermutet: Soll 156, gemalt 167,6.
    implicitWidth: bloecke.implicitWidth
    implicitHeight: Theme.cellH

    // Ein Zeichen je Zelle, in zwei Stuecken nebeneinander -- gefuellt und
    // gedaempft. Vorher war es ein Text mit `<font>`-Marken und RichText; zwei
    // schlichte Stuecke messen sich einfacher, und gemessen wird hier ja.
    Row {
        id: bloecke

        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Line {
            text: "█".repeat(root.filled)
            color: root.fillColor
        }

        Line {
            text: "░".repeat(Math.max(0, root.cells - root.filled))
            color: Theme.muted
        }
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
