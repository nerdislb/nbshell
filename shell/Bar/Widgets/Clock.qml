import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

// Uhr. Das Format steht in der Config (`clockFormat`), damit man es ohne
// Codeaenderung kuerzen kann.
Cell {
    id: root

    readonly property string format: Config.value("clockFormat", "ddd dd.MM  HH:mm")

    // Ueber die Locale formatiert, nicht ueber Qt.formatDateTime: das nimmt
    // die C-Locale und schreibt "Sat" statt "Sa".
    text: clock.date.toLocaleString(Qt.locale(Config.value("locale", "de_DE")), format)
    color: Theme.fg

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
