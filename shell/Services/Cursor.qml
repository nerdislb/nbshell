pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Der Mauszeiger.
//
// Cursor settings are mirrored to Umbriel and GTK. nbshell configuration is
// the source of truth so both consumers change together.
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
    property bool themesLoaded: false

    readonly property string theme: Config.value("cursorTheme", "")
    readonly property int size: Config.value("cursorSize", 24)

    function refresh() {
        if (!lister.running)
            lister.running = true;
    }

    function ensureThemes() {
        if (!themesLoaded)
            refresh();
    }

    function apply() {
        if (root.theme === "")
            return;
        setter.command = ["bash", root.script, "apply", root.theme, String(root.size)];
        setter.running = true;
    }

    // Beim Blaettern im Menue aendert sich der Wert bei jedem Tastendruck. Ohne
    // die kurze Ruhe schriebe jeder davon eine Datei und riefe zweimal
    // gsettings and one Umbriel config reload.
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

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const candidate = JSON.parse(text);
                    if (!Array.isArray(candidate))
                        throw new Error("Cursor themes must be an array");
                    root.themes = candidate;
                    root.themesLoaded = true;
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
