import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Uhr. Das Format steht in der Config (`clockFormat`), damit man es ohne
// Codeaenderung kuerzen kann.
//
// Ein Klick klappt den Kalender auf -- die Stelle, an der man ihn sucht.
Cell {
    id: root

    readonly property string format: Config.value("clockFormat", "ddd dd.MM  HH:mm")

    // Ueber die Locale formatiert, nicht ueber Qt.formatDateTime: das nimmt
    // die C-Locale und schreibt "Sat" statt "Sa".
    text: clock.date.toLocaleString(Qt.locale(Config.value("locale", "de_DE")), format)
    icon: Icons.clock
    color: Theme.text
    interactive: Config.value("calendar", true)

    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.calendarOpen = root.popoutVisible

    Connections {
        target: Runtime

        function onCalendarOpenChanged() {
            root.setPopout(Runtime.calendarOpen);
        }
    }

    popout: Config.value("calendar", true) ? calendarPopout : null

    Component {
        id: calendarPopout

        CalendarPanel {}
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
