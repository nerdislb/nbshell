import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// CPU- und Speicherlast in einer Zelle. Die Zahlen sind auf zwei Stellen
// aufgefuellt, damit die Zelle beim Zaehlen nicht springt.
Cell {
    id: root

    function pad(n) {
        return (n < 10 ? " " : "") + n;
    }

    text: "CPU " + pad(SysInfo.cpuPercent) + "%  RAM " + pad(SysInfo.memPercent) + "%"
    color: SysInfo.cpuPercent >= 90 ? Theme.red : Theme.text
}
