import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Uhr. Das Format steht in der Config (`clockFormat`), damit man es ohne
// Codeaenderung kuerzen kann.
//
// Ein Klick oeffnet das Dashboard mit Kalender, Wetter, Medien und Werkzeugen.
// Ein Rechtsklick geht reihum durch `clockFormats`: die lange Form, die kurze,
// die Kalenderwoche, das amerikanische 12-Stunden-Format. Wer ein eigenes
// Format setzt, das nicht in der Liste steht, faengt beim naechsten
// Rechtsklick vorne an -- die Liste ist ein Vorschlag, kein Zwang.
//
// `%W` und `%M` sind die beiden eigenen Platzhalter: Qts Locale-Formate kennen
// weder die Kalenderwoche noch die Mondphase, beides rechnet der Kalenderdienst
// aus. Der Mond ist von omacal geborgt, das ihn ebenfalls neben der Uhr traegt.
Cell {
    id: root

    readonly property string format: Config.value("clockFormat", "ddd dd.MM  HH:mm")
    readonly property var formats: Config.value("clockFormats", ["ddd dd.MM  HH:mm", "HH:mm", "'KW'%W  ddd  HH:mm", "ddd dd.MM  HH:mm  %M", "ddd dd.MM  h:mm AP"])

    // Ueber die Locale formatiert, nicht ueber Qt.formatDateTime: das nimmt
    // die C-Locale und schreibt "Sat" statt "Sa".
    text: {
        let out = clock.date.toLocaleString(Qt.locale(Config.value("locale", "de_DE")), root.format);
        if (out.indexOf("%W") >= 0)
            out = out.replace("%W", Calendar.isoWeek(clock.date));
        if (out.indexOf("%M") >= 0)
            out = out.replace("%M", Icons.moon(Calendar.moonIndex(clock.date, Icons.moonSteps)));
        return out;
    }
    // Die Uhr erklaert sich selbst; ein Uhrsymbol daneben wiederholt nur ihre
    // Bedeutung und verschiebt die echte Mitte um ein Zeichen.
    icon: ""
    color: Theme.text
    // Auch ohne Kalender anklickbar: der Rechtsklick schaltet das Format, und
    // `clickable` haengt an `interactive` -- stuende hier die Kalenderoption,
    // waere die Uhr ohne khal ein totes Feld.
    interactive: true

    onClicked: Runtime.dashboardOpen = true

    onRightClicked: {
        const list = root.formats;
        if (!Array.isArray(list) || list.length === 0)
            return;
        const at = list.indexOf(root.format);
        Config.set("clockFormat", list[(at + 1) % list.length]);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
