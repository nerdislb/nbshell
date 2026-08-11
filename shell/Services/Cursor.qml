pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Der Mauszeiger.
//
// Anders als bei Theme oder Schriftgroesse gehoert der Zeiger nicht nbshell,
// sondern niri -- und GTK haelt noch eine zweite Meinung dazu. Deshalb ist die
// Config hier die Wahrheit und beide anderen Stellen werden nachgezogen,
// sobald sich `cursorTheme` oder `cursorSize` aendert. Wer den Wert im
// Optionsmenue durchblaettert, sieht den Zeiger sofort wechseln.
//
// Leeres `cursorTheme` heisst: nbshell laesst die Finger davon. Auf einem
// Rechner, auf dem jemand seinen Zeiger schon anders eingerichtet hat, soll
// die blosse Anwesenheit der Shell nichts umstellen.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("../scripts/cursors.sh").toString().replace("file://", "")

    property var themes: []

    readonly property string theme: Config.value("cursorTheme", "")
    readonly property int size: Config.value("cursorSize", 24)

    function refresh() {
        lister.running = true;
    }

    function apply() {
        if (root.theme === "")
            return;
        setter.command = ["bash", root.script, "apply", root.theme, String(root.size)];
        setter.running = true;
    }

    // Beim Blaettern im Menue aendert sich der Wert bei jedem Tastendruck. Ohne
    // die kurze Ruhe schriebe jeder davon eine Datei und riefe zweimal
    // gsettings -- und niri laedt bei jeder Aenderung seine Config neu.
    Timer {
        id: settle

        interval: 250
        onTriggered: root.apply()
    }

    onThemeChanged: settle.restart()
    onSizeChanged: settle.restart()

    Process {
        id: lister

        command: ["bash", root.script, "list"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.themes = JSON.parse(text);
                } catch (e) {
                    console.warn("nbshell/cursor: Themenliste unlesbar —", e);
                    root.themes = [];
                }
            }
        }
    }

    Process {
        id: setter
    }
}
