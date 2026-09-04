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

    function currentIndex() {
        for (var i = 0; i < options.length; i++)
            if (valueOf(options[i]) === current)
                return i;
        return options.length > 0 ? 0 : -1;
    }

    function chooseAndFocus(index) {
        if (options.length === 0)
            return;
        const next = Math.max(0, Math.min(options.length - 1, index));
        chosen(valueOf(options[next]));
        Qt.callLater(() => entries.itemAt(next)?.forceActiveFocus());
    }

    width: root.rowWidth
    // `Flow` kennt nur EINEN Abstand fuer beide Richtungen. Gemessen wird er
    // deshalb an der Zeilenhoehe: waagerecht darf es eng sein, senkrecht
    // klebten die umgebrochenen Kaestchen sonst aneinander.
    spacing: Math.round(Theme.cellH * 0.3)

    Repeater {
        id: entries
        model: root.options

        InteractiveSurface {
            id: segment

            required property var modelData
            required property int index

            readonly property bool active: root.valueOf(segment.modelData) === root.current

            width: Math.min(root.rowWidth > 0 ? root.rowWidth : Number.MAX_VALUE,
                Math.max(Theme.cellW * 4, text.implicitWidth + Theme.cellW * 2))
            height: Theme.controlHeight
            radius: Theme.radius
            border.width: Theme.controlBorderWidth(hover.hovered, segment.active, false)
            border.color: Theme.controlBorder(hover.hovered, segment.active, false)
            color: segment.active ? Theme.selectedSurface(Theme.accent) : (hover.hovered ? Theme.hover : "transparent")
            keyboardFocusable: segment.active || root.currentIndex() < 0
            accessibleRole: Accessible.RadioButton
            accessibleName: root.labelOf(segment.modelData)
            accessibleDescription: segment.active ? "Selected option" : "Option"
            accessibleCheckable: true
            accessibleChecked: segment.active
            onTriggered: root.chosen(root.valueOf(segment.modelData))

            Keys.onLeftPressed: root.chooseAndFocus(segment.index - 1)
            Keys.onRightPressed: root.chooseAndFocus(segment.index + 1)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home) {
                    root.chooseAndFocus(0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    root.chooseAndFocus(root.options.length - 1);
                    event.accepted = true;
                }
            }

            Line {
                id: text

                anchors.centerIn: parent
                width: parent.width - Theme.cellW * 1.2
                text: root.labelOf(segment.modelData)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                // Das gefuellte Kaestchen bestimmt die Textfarbe mit -- sonst
                // steht bei einem hellen Theme dunkles Grau auf dunklem Grund.
                color: segment.active ? Theme.selectedForeground(Theme.accent) : Theme.fg
                font.pixelSize: Theme.fontBody
            }

            HoverHandler {
                id: hover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: {
                    segment.forceActiveFocus();
                    segment.activate();
                }
            }
        }
    }
}
