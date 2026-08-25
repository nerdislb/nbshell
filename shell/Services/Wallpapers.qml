pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Alle bekannten Bilder, ueber Theme-Grenzen hinweg.
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

    function restoreForTheme(theme) {
        const map = Config.value("wallpaperByTheme", {});
        Config.set("wallpaperOverride", map[theme] ?? "");
        root.refresh();
    }

    Component.onCompleted: {
        // Heal stale overrides left by older sessions where this singleton
        // was only created after opening the wallpaper picker.
        const initialTheme = Config.theme;
        Qt.callLater(() => {
            if (Config.theme === initialTheme)
                root.restoreForTheme(initialTheme);
        });
    }

    function refresh() {
        loading = true;
        proc.command = ["sh", "-c", root.findCommand(Config.theme)];
        proc.running = true;
    }

    function findCommand(theme) {
        const home = Quickshell.env("HOME");
        const data = Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share");
        const roots = [Config.themeDir, data + "/nbshell/wallpapers", home + "/Sync/nbshell/wallpapers"];
        // Every immediate child is a theme collection. Config themes keep
        // their images one level deeper in `backgrounds`; the two wallpaper
        // roots store them directly below the theme name. Emit metadata with
        // every path so identical numbered names such as `1.webp` remain
        // distinguishable in the global picker.
        return "for root in " + roots.map(d => JSON.stringify(d)).join(" ") +
            "; do for d in \"$root\"/*; do [ -d \"$d\" ] || continue; " +
            "theme=$(basename \"$d\"); [ -d \"$d/backgrounds\" ] && d=\"$d/backgrounds\"; " +
            "find \"$d\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | sort | " +
            "while IFS= read -r f; do printf '%s\\t%s\\n' \"$theme\" \"$f\"; done; done; done";
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

    function nameOf(item) {
        const path = item?.path ?? item ?? "";
        return String(path).split("/").pop();
    }

    function themeOf(item) {
        return item?.theme ?? "unknown";
    }

    function pathOf(item) {
        return item?.path ?? item ?? "";
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                const seen = ({});
                root.list = text.split("\n").map(line => {
                    const tab = line.indexOf("\t");
                    if (tab < 1)
                        return null;
                    const item = { "theme": line.slice(0, tab), "path": line.slice(tab + 1).trim() };
                    const key = item.theme + "/" + root.nameOf(item);
                    if (!item.path || seen[key])
                        return null;
                    seen[key] = true;
                    return item;
                }).filter(item => item !== null);
                root.loading = false;
                // Dotfiles speichern absolute Wallpaper-Pfade. Auf einem
                // zweiten Rechner kann derselbe Dateiname aus Syncthing an
                // einem anderen der drei Orte liegen. Dann den alten Pfad
                // automatisch auf das gefundene Bild desselben Namens heilen.
                const selected = root.current;
                if (selected && !root.list.some(item => item.path === selected)) {
                    const wanted = root.nameOf(selected);
                    const replacement = root.list.find(item => root.nameOf(item) === wanted);
                    if (replacement)
                        root.apply(replacement.path);
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
                root.restoreForTheme(changedTheme);
            });
        }
    }
}
