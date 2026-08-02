pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Die Bilder des aktuellen Themes.
//
// Gesucht wird an denselben drei Stellen wie in scripts/themes.sh: beim Theme
// selbst, im Zwischenspeicher von omarchy2dms (den teilen sich beide) und
// unter ~/.local/share/nbshell/wallpapers.
//
// Bewusst OHNE Zwischenspeicher: die Liste wird bei jedem Oeffnen frisch
// gelesen. Ein Cache hat in der Vorlage (themeWallpaper) genau das kaputt
// gemacht -- die Auswahl liess sich mit den Pfeiltasten bewegen, aber Enter
// nahm den alten Stand.
Singleton {
    id: root

    property var list: []
    property bool loading: false

    readonly property string current: Config.value("wallpaperOverride", "")

    function refresh() {
        loading = true;
        proc.command = ["sh", "-c", root.findCommand(Config.theme)];
        proc.running = true;
    }

    function findCommand(theme) {
        const home = Quickshell.env("HOME");
        const data = Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share");
        const dirs = [Config.themeDir + "/" + theme + "/backgrounds", data + "/omarchy2dms/wallpapers/" + theme, data + "/nbshell/wallpapers/" + theme];
        // `find` statt `ls`: es kennt mehrere Endungen in einem Aufruf und
        // stolpert nicht ueber Leerzeichen in Namen.
        return "find " + dirs.map(d => JSON.stringify(d)).join(" ") + " -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort";
    }

    function apply(path) {
        Config.set("wallpaperOverride", path);
        // Ein gewaehltes Bild ohne sichtbaren Hintergrund waere eine
        // Enttaeuschung -- also gleich einschalten.
        if (!Config.wallpaperEnabled)
            Config.set("wallpaper", true);
    }

    // Zurueck zum Bild, das das Theme selbst mitbringt.
    function reset() {
        Config.set("wallpaperOverride", "");
    }

    function nameOf(path) {
        return String(path).split("/").pop();
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                root.list = text.split("\n").map(l => l.trim()).filter(l => l.length > 0);
                root.loading = false;
            }
        }
    }

    // Themewechsel heisst neue Bilder.
    Connections {
        target: Config

        function onDataChanged() {
            if (Runtime.wallpaperOpen)
                root.refresh();
        }
    }
}
