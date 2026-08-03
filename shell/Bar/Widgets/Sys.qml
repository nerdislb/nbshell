import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// CPU- und Speicherlast in einer Zelle. Die Zahlen sind auf zwei Stellen
// aufgefuellt, damit die Zelle beim Zaehlen nicht springt.
//
// Zwei Werte, zwei Symbole -- deshalb baut dieser Baustein seine Zeile selbst,
// statt das eine Symbol der Zelle zu benutzen. Ohne Symbole stehen wieder die
// Kuerzel davor, sonst waeren es zwei nackte Prozentzahlen nebeneinander.
Cell {
    id: root

    function pad(n) {
        return (n < 10 ? " " : "") + n;
    }

    custom: true
    color: SysInfo.cpuPercent >= 90 ? Theme.red : Theme.text

    Row {
        spacing: Theme.cellW * 1.5

        IconText {
            icon: Icons.cpu
            text: (Config.widgetIcons ? "" : "CPU ") + root.pad(SysInfo.cpuPercent) + "%"
            color: root.color
        }

        IconText {
            icon: Icons.memory
            text: (Config.widgetIcons ? "" : "RAM ") + root.pad(SysInfo.memPercent) + "%"
            color: Theme.text
        }
    }
}
