import QtQuick
import qs.Common

// Eine Reihe gerahmter Kaestchen, das aktive gefuellt:
//
//   [ DHCP ] [Cloudflare] [ Google ] [ Custom ]
//
// Der Punkt ist nicht die Optik, sondern was man sieht: nbshell schaltet
// Aufzaehlungen bisher blind weiter -- ein Klick auf die Zelle, und die Form
// der Leiste ist eine andere. Was es SONST noch gaebe, stand nirgends. Hier
// stehen alle Moeglichkeiten nebeneinander, und welche gilt, ist gefuellt.
//
//   Segments {
//       rowWidth: panel.rowWidth
//       options: ["balanced", "powersave"]
//       current: PowerService.activeProfile
//       onChosen: value => PowerService.setProfile(value)
//   }
//
// Eintraege duerfen auch Objekte sein (`{ label, value }`), wenn der Text
// nicht der Wert ist -- "Insel" heisst in der Config `island`.
//
// Ein `Flow` und keine `Row`: tuneds Profile heissen Dinge wie
// "throughput-performance", und drei davon nebeneinander waeren breiter als
// jedes Popout. Sie brechen dann eben um, statt hinauszuragen.
Flow {
    id: root

    property var options: []
    property var current: null
    property real rowWidth: 0

    signal chosen(var value)

    function valueOf(option) {
        return (option && option.value !== undefined) ? option.value : option;
    }

    function labelOf(option) {
        return String((option && option.label !== undefined) ? option.label : option);
    }

    width: root.rowWidth
    // `Flow` kennt nur EINEN Abstand fuer beide Richtungen. Gemessen wird er
    // deshalb an der Zeilenhoehe: waagerecht darf es eng sein, senkrecht
    // klebten die umgebrochenen Kaestchen sonst aneinander.
    spacing: Math.round(Theme.cellH * 0.3)

    Repeater {
        model: root.options

        Rectangle {
            id: segment

            required property var modelData

            readonly property bool active: root.valueOf(segment.modelData) === root.current

            width: text.implicitWidth + Theme.cellW * 2
            height: Theme.cellH * 1.6
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: segment.active ? Theme.accent : Theme.muted
            color: segment.active ? Theme.selection : (hover.hovered ? Theme.hover : "transparent")

            Line {
                id: text

                anchors.centerIn: parent
                text: root.labelOf(segment.modelData)
                // Das gefuellte Kaestchen bestimmt die Textfarbe mit -- sonst
                // steht bei einem hellen Theme dunkles Grau auf dunklem Grund.
                color: segment.active ? Theme.on(Theme.selection) : Theme.fg
            }

            HoverHandler {
                id: hover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: root.chosen(root.valueOf(segment.modelData))
            }
        }
    }
}
