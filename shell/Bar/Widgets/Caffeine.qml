import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Wachhalten -- der Knopf, der verhindert, dass der Rechner von selbst dimmt,
// abschaltet oder sperrt.
//
// Klick schaltet um. Mehr macht die Zelle nicht; das Popout nennt nur die
// Fristen, damit man nachsehen kann, wann was passiert waere.
//
// **Sichtbar ist sie nur, wenn sie an ist.** Das ist der ganze Trick an dem
// Ding: ein Knopf, der dauernd dasteht, wird zu Moebel, und dann vergisst man,
// dass der Rechner seit drei Tagen wachgehalten wird. Umgekehrt darf der
// Normalfall (alles automatisch) still sein. Deshalb `quiet`, solange kein
// Kaffee da ist -- die Maus in der Leiste holt die Zelle trotzdem hervor.
Cell {
    id: root

    interactive: true
    slotChars: 0

    quiet: !Idle.caffeine
    label: Idle.caffeine ? "WACH" : "IDLE"

    icon: {
        if (Idle.caffeine)
            return Icons.coffee;
        return Idle.enabled ? Icons.sleep : Icons.sleepOff;
    }

    // Gelb ist die Farbe fuer "hier gilt gerade etwas anderes als sonst" --
    // dieselbe, die auch der Updater ab fuenfzig offenen Paketen nimmt.
    color: Idle.caffeine ? Theme.yellow : (Idle.enabled ? Theme.textDim : Theme.muted)

    onClicked: Idle.toggleCaffeine()

    // Rechtsklick schaltet die ganze Automatik ab, nicht nur diese Runde. Das
    // ist der seltenere Wunsch, deshalb die seltenere Geste.
    onRightClicked: Config.set("idle", !Idle.enabled)

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 40 * Theme.cellW

            spacing: Theme.cellH * 0.2

            function minuten(sekunden) {
                if (sekunden <= 0)
                    return "off";
                if (sekunden < 60)
                    return sekunden + " s";
                const m = Math.round(sekunden / 60);
                return m + " min";
            }

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Idle.caffeine ? Icons.coffee : Icons.sleep
                title: Idle.caffeine ? "Keep awake active" : (Idle.enabled ? "Automation active" : "Automation disabled")
                subtitle: "Idle behavior"
                badge: Idle.state
                badgeColor: Idle.caffeine ? Theme.yellow : Theme.fgDim
            }

            Facts {
                rowWidth: panel.rowWidth
                columns: 1
                pairs: [
                    {
                        "label": "dim after",
                        "value": panel.minuten(Idle.dimAfter),
                        "color": Idle.armed ? Theme.fg : Theme.muted
                    },
                    {
                        "label": "Screen off after",
                        "value": panel.minuten(Idle.offAfter),
                        "color": Idle.armed ? Theme.fg : Theme.muted
                    },
                    {
                        "label": "lock after",
                        "value": panel.minuten(Idle.lockAfter),
                        "color": Idle.armed ? Theme.fg : Theme.muted
                    }
                ]
            }

            Rule {
                rowWidth: panel.rowWidth
            }

            Line {
                width: panel.rowWidth
                text: Idle.caffeine ? "Click to enable automation again." : "Click to keep the computer awake."
                color: Theme.fgDim
                wrapMode: Text.WordWrap
            }

            Line {
                width: panel.rowWidth
                text: "Right-click turns automation " + (Idle.enabled ? "off completely." : "back on.")
                color: Theme.muted
                wrapMode: Text.WordWrap
            }

            Line {
                width: panel.rowWidth
                visible: !Brightness.available
                text: "No brightness control found -- dimming is disabled."
                color: Theme.muted
                wrapMode: Text.WordWrap
                topPadding: Theme.cellH * 0.3
            }
        }
    }
}
