import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Akkus der angeschlossenen Geraete -- Maus, Kopfhoerer, Tastatur.
//
// Die Zahlen lagen schon vor: BlueZ meldet sie, und das Control-Popout zeigte
// sie ganz unten in der Geraeteliste. Nur sieht man sie dort nie, und eine
// Maus, die morgen leer ist, faellt einem erst auf, wenn sie es ist.
//
// Die Zelle meldet sich deshalb selbst -- aber nur, wenn es etwas zu melden
// gibt: solange alles ueber `deviceLowAt` (30 %) steht, ist sie `quiet` und
// damit unsichtbar. Sie ist kein Dauerbewohner der Leiste, sondern eine
// Erinnerung.
//
// Das Headset am USB-Dongle steht NICHT hier drin: das ist kein
// Bluetooth-Geraet und kommt ueber das `headset`-Plugin (headsetcontrol).
Cell {
    id: root

    readonly property var lowest: Bt.lowest

    shown: Bt.available && root.lowest !== null
    quiet: root.lowest === null || root.lowest.percent > Bt.lowAt
    interactive: true
    slotChars: 4

    label: root.lowest ? root.lowest.label.substring(0, 6).toUpperCase() : "DEV"
    icon: root.lowest ? Icons.battery(root.lowest.percent) : Icons.battery(100)
    text: root.lowest ? (root.lowest.percent + "%") : ""

    color: {
        if (!root.lowest)
            return Theme.textDim;
        if (root.lowest.percent <= Bt.warnAt)
            return Theme.red;
        return root.lowest.percent <= Bt.lowAt ? Theme.yellow : Theme.text;
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 40 * Theme.cellW

            spacing: Theme.cellH * 0.2

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.battery(Bt.lowest ? Bt.lowest.percent : 100)
                title: "Geraete"
                subtitle: "Bluetooth"
                badge: Bt.withBattery.length > 0 ? String(Bt.withBattery.length) : ""
            }

            Facts {
                rowWidth: panel.rowWidth
                columns: 1
                pairs: Bt.withBattery.map(d => ({
                            "label": d.label,
                            "value": d.percent + " %",
                            "color": d.percent <= Bt.warnAt ? Theme.red : (d.percent <= Bt.lowAt ? Theme.yellow : Theme.fg)
                        }))
            }

            // Verbundene Geraete OHNE Akkumeldung: sie fehlen sonst wortlos,
            // und man sucht den Fehler bei der Zelle statt beim Geraet.
            Text {
                width: panel.rowWidth
                visible: Bt.connected.length > Bt.withBattery.length
                text: "  " + (Bt.connected.length - Bt.withBattery.length) + " verbunden, ohne Akkumeldung"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                topPadding: Theme.cellH * 0.3
            }

            Text {
                width: panel.rowWidth
                visible: Bt.withBattery.length === 0
                text: "  kein Geraet meldet seinen Akku"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }
        }
    }
}
