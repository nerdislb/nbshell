pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Verzeichnis aller Themes -- der Teil von omarchy2dms, den nbshell noch
// braucht.
//
// Umrechnen muss hier nichts mehr: die Shell liest Omarchys `colors.toml`
// direkt, es gibt kein Zielformat. Uebrig bleibt das Suchen und Auflisten, und
// das erledigt ein kleines Skript (scripts/themes.sh) -- Verzeichnisse zu
// durchsuchen ist in QML muehsam, in einer Zeile Shell nicht.
//
// Gelesen wird einmal beim Start und danach nur auf Zuruf: die Liste aendert
// sich nur, wenn jemand Themes installiert.
Singleton {
    id: root

    property var list: []
    property bool loading: false

    readonly property var current: byName(Config.theme)

    function byName(name) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === name)
                return list[i];
        }
        return null;
    }

    function refresh() {
        loading = true;
        proc.running = true;
    }

    function apply(name) {
        Config.set("theme", name);
    }

    // Vor und zurueck durch die Liste -- fuer Tastenkuerzel.
    function step(delta) {
        if (list.length === 0)
            return;
        var i = list.findIndex(t => t.name === Config.theme);
        if (i < 0)
            i = 0;
        const next = (i + delta + list.length) % list.length;
        apply(list[next].name);
    }

    Process {
        id: proc

        command: [Qt.resolvedUrl("../scripts/themes.sh").toString().replace("file://", ""), Config.themeDir]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.list = JSON.parse(text);
                } catch (e) {
                    console.warn("nbshell: Themeliste unlesbar —", e);
                    root.list = [];
                }
                root.loading = false;
            }
        }
    }
}
