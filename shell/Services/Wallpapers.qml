pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Die Bilder des aktuellen Themes.
//
// Gesucht wird beim Theme selbst, im eigenen nbshell-Datenbereich und im
// zwischen Rechnern synchronisierten ~/Sync/nbshell/wallpapers.
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
        const dirs = [
            Config.themeDir + "/" + theme + "/backgrounds",
            data + "/nbshell/wallpapers/" + theme,
            home + "/Sync/nbshell/wallpapers/" + theme
        ];
        // `find` statt `ls`: es kennt mehrere Endungen in einem Aufruf und
        // stolpert nicht ueber Leerzeichen in Namen.
        // Pro Quelle sortieren und danach gleiche Dateinamen aus spaeteren
        // Quellen ausblenden. Auf dem Hauptrechner liegen dieselben Bilder
        // oft beim Theme UND in Syncthing; ohne Deduplizierung erschiene jedes
        // davon zweimal im Karussell.
        return "for d in " + dirs.map(d => JSON.stringify(d)).join(" ") +
            "; do find \"$d\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort; done | awk -F/ '!seen[$NF]++'";
    }

    // Die Wahl gilt FUER DAS THEME, nicht fuer immer.
    //
    // Vorher blieb ein einmal gewaehltes Bild bei jedem Themewechsel stehen --
    // und weil der Hintergrund das Auffaelligste am Bildschirm ist, sah es aus,
    // als taete der Wechsel gar nichts. Gemerkt wird deshalb je Theme; wer
    // zurueckwechselt, bekommt sein Bild wieder.
    function apply(path) {
        const map = JSON.parse(JSON.stringify(Config.value("wallpaperByTheme", {})));
        map[Config.theme] = path;
        Config.set("wallpaperByTheme", map);
        Config.set("wallpaperOverride", path);
        // Ein gewaehltes Bild ohne sichtbaren Hintergrund waere eine
        // Enttaeuschung -- also gleich einschalten.
        if (!Config.wallpaperEnabled)
            Config.set("wallpaper", true);
    }

    // Zurueck zum Bild, das das Theme selbst mitbringt.
    function reset() {
        const map = JSON.parse(JSON.stringify(Config.value("wallpaperByTheme", {})));
        delete map[Config.theme];
        Config.set("wallpaperByTheme", map);
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
                // Dotfiles speichern absolute Wallpaper-Pfade. Auf einem
                // zweiten Rechner kann derselbe Dateiname aus Syncthing an
                // einem anderen der drei Orte liegen. Dann den alten Pfad
                // automatisch auf das gefundene Bild desselben Namens heilen.
                const selected = root.current;
                if (selected && root.list.indexOf(selected) < 0) {
                    const wanted = root.nameOf(selected);
                    const replacement = root.list.find(path => root.nameOf(path) === wanted);
                    if (replacement)
                        root.apply(replacement);
                    else
                        root.reset();
                }
            }
        }
    }

    // NUR beim Themewechsel neu lesen, nicht bei jeder Config-Aenderung:
    // das Karussell schreibt beim Blaettern selbst in die Config, und ein
    // Neulesen mitten im Blaettern warf die Auswahl jedes Mal zurueck.
    Connections {
        target: Config

        function onThemeChanged() {
            // Config.set("theme", …) schreibt seinen Snapshot erst fertig,
            // nachdem dieses Signal zurueckkehrt. Ein synchrones set() hier
            // wurde deshalb danach wieder vom alten wallpaperOverride dieses
            // Snapshots ueberschrieben (sichtbar: Harbor blieb nach dem
            // Zurueckwechseln stehen). Einen Event-Loop-Takt spaeter ist der
            // Theme-Schreibvorgang abgeschlossen und unsere Wahl gewinnt.
            const changedTheme = Config.theme;
            Qt.callLater(() => {
                // Schnelles Durchschalten: nur der letzte Themewechsel darf
                // noch ein Bild anwenden.
                if (Config.theme !== changedTheme)
                    return;
                const map = Config.value("wallpaperByTheme", {});
                Config.set("wallpaperOverride", map[changedTheme] ?? "");
                root.refresh();
            });
        }
    }
}
