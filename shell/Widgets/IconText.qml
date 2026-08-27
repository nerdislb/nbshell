import QtQuick
import qs.Common

// Symbol und Text nebeneinander, beides auf dem Zeichenraster.
//
// Das Symbol ist abschaltbar (`widgetIcons` in der Config): wer die Leiste
// lieber als reine Textzeile haette, bekommt sie -- die Bausteine bleiben
// dieselben, es faellt nur das Zeichen weg. Steht kein Text daneben, faellt
// auch der Abstand weg, sonst saesse das Symbol nicht mittig in seiner Zelle.
Row {
    id: root

    property string icon: ""
    property string text: ""
    property color color: Theme.fg

    // Dreht sich, solange etwas laeuft (Updatepruefung). Steht danach wieder
    // gerade, statt schief stehen zu bleiben.
    property bool spins: false

    property real iconHeight: Math.round(Theme.cellH * 0.72)
    property bool fixedIconSlot: true

    // Vorgabe ist die allgemeine Einstellung; `Cell` setzt hier das Ergebnis
    // seiner eigenen Rechnung hinein, weil ein Baustein sie ueberschreiben
    // darf (`widgets.<id>.display`).
    property bool icons: Config.widgetIcons

    readonly property bool showIcon: root.icon !== "" && root.icons

    spacing: (showIcon && root.text !== "") ? Math.round(Theme.cellW * 0.6) : 0

    // Die Kinder eines Positionierers duerfen selbst KEINE Anker haben --
    // sonst rechnet die Reihe mit Breite 0. Deshalb je ein Kaestchen auf
    // Zeilenhoehe, in dem Zeichen und Text dann mittig sitzen duerfen.
    Item {
        // Die Breite der Zeichnung, nicht die der Zelle: sonst steht neben
        // schmalen Symbolen ein Loch, das nur aus Vorschub besteht.
        width: root.showIcon ? (root.fixedIconSlot ? Theme.barIconSlot : Math.ceil(mark.inkWidth)) : 0
        height: Theme.cellH
        visible: root.showIcon

        Glyph {
            id: mark

            anchors.centerIn: parent
            anchors.horizontalCenterOffset: mark.inkOffsetX
            text: root.icon
            color: root.color
            inkHeight: root.fixedIconSlot ? Theme.barIconHeight : root.iconHeight

            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: Theme.motionLoopSlow
                loops: Animation.Infinite
                running: root.spins && !Theme.reducedMotion

                onRunningChanged: if (!running)
                    mark.rotation = 0
            }
        }
    }

    Item {
        width: label.implicitWidth
        height: Theme.cellH
        visible: root.text !== ""

        Line {
            id: label

            anchors.centerIn: parent
            text: root.text
            color: root.color
        }
    }
}
