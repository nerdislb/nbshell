import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services

// Steuerung von aussen: Aussehen.
//
// Leiste, Themes, Akzentfarben, einzelne Bausteine, Hintergrund.
//
// Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell. Diese Handler
// standen frueher alle in shell.qml -- 945 von 1088 Zeilen, sodass die
// eigentliche Frage "woraus besteht diese Shell?" unter der Fernsteuerung
// begraben lag. Sie sprechen ausschliesslich mit Singletons, also war der
// Schnitt schmerzlos.
Scope {
    IpcHandler {
        target: "bar"

        function mode(value: string): string {
            // `toggle` geht seit der Pille im Kreis statt hin und her. Ein
            // unbekannter Wert in der Config landet dabei auf "island" --
            // indexOf gibt -1, und -1 + 1 ist die erste Form.
            const order = ["island", "pill", "bar"];
            const next = value === "toggle" ? order[(order.indexOf(Config.mode) + 1) % order.length] : value;
            if (order.indexOf(next) < 0)
                return "unknown: " + value + " (island|pill|bar|toggle)";
            // Each shape starts in its canonical state. In particular, an
            // old transient popout reveal must not keep Island expanded.
            Runtime.islandTransient = false;
            Runtime.islandOpen = false;
            Config.set("mode", next);
            return next;
        }

        function edge(value: string): string {
            const next = value === "toggle" ? (Config.edge === "top" ? "bottom" : "top") : value;
            if (next !== "top" && next !== "bottom")
                return "unknown: " + value + " (top|bottom|toggle)";
            Config.set("edge", next);
            return next;
        }

        function open(): string {
            Runtime.islandTransient = false;
            Runtime.islandOpen = true;
            return "open";
        }

        function close(): string {
            Runtime.islandTransient = false;
            Runtime.islandOpen = false;
            return "closed";
        }

        function toggle(): string {
            Runtime.islandTransient = false;
            Runtime.islandOpen = !Runtime.islandOpen;
            return Runtime.islandOpen ? "open" : "closed";
        }

        function status(): string {
            return JSON.stringify({
                "mode": Config.mode,
                "edge": Config.edge,
                "theme": Config.theme,
                "open": Runtime.islandOpen,
                "screens": Quickshell.screens.length
            });
        }
    }

    IpcHandler {
        target: "theme"

        function set(name: string): string {
            // Ein Name ohne Verzeichnis waere ein Theme ohne Farben -- die
            // Shell faellt dann auf ihre Vorgaben zurueck und man sucht den
            // Fehler woanders.
            if (!ThemeIndex.byName(name))
                return "unknown theme: " + name;
            Config.set("theme", name);
            return name;
        }

        function current(): string {
            return Config.theme;
        }

        // Schreibt die Farbdateien neu, ohne das Theme zu wechseln.
        // NICHT `export` nennen -- das ist in JavaScript ein Schluesselwort,
        // und die ganze Datei laedt dann nicht mehr.
        function write(): string {
            ThemeExport.exportNow();
            return "geschrieben";
        }

        // Der Akzent als Rolle. `theme` heisst: was das Theme selbst
        // vorschlaegt.
        function accent(role: string): string {
            if (!role || role === "status") {
                return Theme.accentRole + "  (" + String(Theme.accent) + ")\n" + Theme.accentRoles.map(r => (r === Theme.accentRole ? "▸ " : "  ") + r + "  " + String(Theme.roleColor(r))).join("\n");
            }
            const wish = String(role).toLowerCase();
            if (Theme.accentRoles.indexOf(wish) < 0)
                return "unknown role: " + role + "  (" + Theme.accentRoles.join(" ") + ")";
            Config.set("accent", wish);
            return wish + "  " + String(Theme.roleColor(wish));
        }
    }

    // Aussehen einzelner Bausteine. Alles hier schreibt in `widgets` in der
    // Config; was nicht gesetzt ist, kommt weiter aus der allgemeinen
    // Einstellung.
    // Die erlaubten Werte stehen NEBEN dem IpcHandler, nicht darin: alles, was
    // dort als Property haengt, versucht Quickshell ueber IPC anzubieten -- und
    // meldet bei jedem Start "Type QVariant cannot be used across IPC".
    QtObject {
        id: widgetOptions

        readonly property var keys: ["display", "style", "color"]

        readonly property var choices: ({
                "display": ["auto", "full", "icon", "text"],
                "style": ["auto", "box", "plain"],
                "color": ["auto", "theme", "red", "green", "yellow", "blue", "magenta", "cyan", "orange", "foreground"]
            })
    }

    IpcHandler {
        target: "widget"

        function list(): string {
            const all = Config.value("widgets", ({})) ?? ({});
            const names = Object.keys(all);
            if (names.length === 0)
                return "no overrides — all modules use the global settings\n\nnbshell widget <module> display|style|color <value>";
            return names.map(n => (n + "            ").substring(0, 12) + widgetOptions.keys.filter(k => all[n][k]).map(k => k + "=" + all[n][k]).join("  ")).join("\n");
        }

        function set(name: string, key: string, value: string): string {
            if (!name)
                return "module is missing";
            if (widgetOptions.keys.indexOf(key) < 0)
                return "unknown: " + key + "  (" + widgetOptions.keys.join(" ") + ")";
            if (widgetOptions.choices[key].indexOf(value) < 0)
                return "unknown: " + value + "  (" + widgetOptions.choices[key].join(" ") + ")";

            // Kopieren statt aendern: `Config.set` vergleicht das Objekt, und
            // eine Aenderung IN der vorhandenen Struktur bliebe unbemerkt.
            const all = JSON.parse(JSON.stringify(Config.value("widgets", ({})) ?? ({})));
            const one = all[name] ?? ({});
            if (value === "auto")
                delete one[key];
            else
                one[key] = value;

            // Ein leerer Eintrag ist kein Eintrag: sonst sammelt die Config
            // Namen ohne Inhalt an.
            if (Object.keys(one).length === 0)
                delete all[name];
            else
                all[name] = one;

            Config.set("widgets", all);
            return name + ": " + key + " = " + value;
        }

        function reset(name: string): string {
            const all = JSON.parse(JSON.stringify(Config.value("widgets", ({})) ?? ({})));
            if (!name || name === "all") {
                Config.set("widgets", ({}));
                return "alle Ueberschreibungen entfernt";
            }
            if (!all[name])
                return name + " hatte keine";
            delete all[name];
            Config.set("widgets", all);
            return name + " now follows the global settings";
        }
    }

    IpcHandler {
        target: "wallpaper"

        function on(): string {
            Config.set("wallpaper", true);
            return "an";
        }

        function off(): string {
            Config.set("wallpaper", false);
            return "aus";
        }

        function toggle(): string {
            return Config.wallpaperEnabled ? off() : on();
        }

        // Ein festes Bild, unabhaengig vom Theme. Leerer Wert -> wieder das
        // Bild des Themes.
        function set(path: string): string {
            Config.set("wallpaperOverride", path);
            return path === "" ? "wieder vom Theme" : path;
        }

        // Das Karussell: die Bilder des aktuellen Themes durchblaettern.
        function pick(): string {
            Runtime.wallpaperOpen = !Runtime.wallpaperOpen;
            return Runtime.wallpaperOpen ? "open" : "closed";
        }

        function list(): string {
            // Die Liste wird sonst erst beim Oeffnen des Karussells gelesen --
            // beim ersten Aufruf hier waere sie leer.
            Wallpapers.refresh();
            if (Wallpapers.list.length === 0)
                return "not loaded yet — run the command again";
            return Wallpapers.list.map(w => Wallpapers.nameOf(w)).join("\n");
        }

        function current(): string {
            return Config.value("wallpaperOverride", "") || (ThemeIndex.current?.wallpaper ?? "");
        }
    }

    IpcHandler {
        target: "themes"

        function list(): string {
            return ThemeIndex.list.map(t => (t.name === Config.theme ? " * " : "   ") + t.name).join("\n");
        }

        // Die Insel klappt mit auf: sonst haengt der Waehler an einer Zelle,
        // die gerade gar nicht zu sehen ist.
        function open(): string {
            Runtime.revealIslandTemporarily();
            Runtime.themePickerOpen = true;
            return "open";
        }

        function close(): string {
            Runtime.themePickerOpen = false;
            return "closed";
        }

        function toggle(): string {
            if (Runtime.themePickerOpen)
                return close();
            return open();
        }

        function next(): string {
            ThemeIndex.step(1);
            return Config.theme;
        }

        function prev(): string {
            ThemeIndex.step(-1);
            return Config.theme;
        }

        function reload(): string {
            ThemeIndex.refresh();
            return "reloaded";
        }
    }
}
