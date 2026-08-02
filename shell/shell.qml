//@ pragma UseQApplication
//@ pragma AppId dev.nerdi.nbshell

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services
import qs.Bar
import qs.Launcher
import qs.Osd
import qs.Notifications
import qs.Power
import qs.Procs
import qs.Capture
import qs.Settings
import qs.Wallpaper

// nbshell -- Einstiegspunkt.
//
// Eine eigene Quickshell-Konfiguration, kein Plugin und kein Fork. DMS bleibt
// daneben installiert und laeuft weiter; die beiden stossen sich nicht, solange
// nbshell keine D-Bus-Namen beansprucht (Benachrichtigungen, Tray) -- das kommt
// erst, wenn hier alles Noetige steht.
ShellRoot {
    id: shell

    Component.onCompleted: {
        // QML-Dateien werden im Betrieb neu geladen. Beim Entwickeln reicht
        // damit Speichern statt Neustarten.
        Quickshell.watchFiles = true;
        console.info("nbshell laeuft — Theme:", Config.theme, "| Modus:", Config.mode);

        // Singletons entstehen in QML erst, wenn sie jemand anfasst. Die
        // Dienste, die von aussen beobachten (Helligkeit, Netz, Bluetooth,
        // Audio, Themeliste), muessen deshalb hier einmal beruehrt werden --
        // sonst faengt der Helligkeitsdienst erst an zu suchen, wenn das
        // Control Center zum ersten Mal aufgeht, und zeigt so lange 0 %.
        void Brightness.available;
        void Net.summary;
        void Bt.available;
        void Audio.ready;
        void ThemeIndex.list;
        void Apps.entries;
        void Osd.enabled;
        void Notify.count;
        void MediaService.active;
        void Clipboard.entries;
        void Procs.list;
        void CaptureService.recording;
        void AiUsage.available;
        void ThemeExport.enabled;
    }

    Bar {}

    Wallpaper {}

    Launcher {}

    Osd {}

    Popups {}

    PowerMenu {}

    ProcessList {}

    CaptureMenu {}

    SettingsMenu {}

    ModulesMenu {}

    WallpaperPicker {}

    // ── Steuerung von aussen ──────────────────────────────────────────────
    // Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell.

    IpcHandler {
        target: "bar"

        function mode(value: string): string {
            const next = value === "toggle" ? (Config.mode === "bar" ? "island" : "bar") : value;
            if (next !== "island" && next !== "bar")
                return "unbekannt: " + value + " (island|bar|toggle)";
            Config.set("mode", next);
            return next;
        }

        function edge(value: string): string {
            const next = value === "toggle" ? (Config.edge === "top" ? "bottom" : "top") : value;
            if (next !== "top" && next !== "bottom")
                return "unbekannt: " + value + " (top|bottom|toggle)";
            Config.set("edge", next);
            return next;
        }

        function open(): string {
            Runtime.islandOpen = true;
            return "offen";
        }

        function close(): string {
            Runtime.islandOpen = false;
            return "zu";
        }

        function toggle(): string {
            Runtime.islandOpen = !Runtime.islandOpen;
            return Runtime.islandOpen ? "offen" : "zu";
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
                return "unbekanntes Theme: " + name;
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
    }

    IpcHandler {
        target: "state"

        // Was gerade offen ist. Nuetzlich beim Suchen, wenn ein Fenster
        // haengt oder gar nicht erst auftaucht.
        //
        // NICHT `show` nennen: `qs ipc call state show` versteht die CLI als
        // ihr eigenes `ipc show` und listet nur die Ziele auf.
        function dump(): string {
            return JSON.stringify({
                "popouts": Runtime.popoutCount,
                "insel": Runtime.islandOpen,
                "starter": Runtime.launcherOpen,
                "einstellungen": Runtime.settingsOpen,
                "bausteine": Runtime.modulesOpen,
                "hintergrund": Runtime.wallpaperOpen,
                "prozesse": Runtime.procsOpen,
                "aufnahme": Runtime.captureOpen,
                "power": Runtime.powerOpen
            });
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): string {
            Runtime.settingsOpen = !Runtime.settingsOpen;
            return Runtime.settingsOpen ? "offen" : "zu";
        }

        function modules(): string {
            Runtime.modulesOpen = !Runtime.modulesOpen;
            return Runtime.modulesOpen ? "offen" : "zu";
        }
    }

    IpcHandler {
        target: "ai"

        function status(): string {
            if (!AiUsage.available)
                return "kein Helferskript gefunden";
            if (AiUsage.list.length === 0)
                return "noch keine Zahlen";
            return AiUsage.list.map(e => e.id + "  " + e.percent + "%  " + e.window + ", " + AiUsage.untilReset(e)).join("\n");
        }

        function refresh(): string {
            AiUsage.refresh();
            return "abgerufen";
        }
    }

    IpcHandler {
        target: "capture"

        function menu(): string {
            Runtime.captureOpen = !Runtime.captureOpen;
            return Runtime.captureOpen ? "offen" : "zu";
        }

        function screen(): string {
            return CaptureService.shoot("screen") ? "Bildschirm" : "niri fehlt";
        }

        function window(): string {
            return CaptureService.shoot("window") ? "Fenster" : "niri fehlt";
        }

        function region(): string {
            return CaptureService.shoot("region") ? "Bereich" : "niri fehlt";
        }

        function ocr(): string {
            return CaptureService.ocr() ? "Texterkennung" : "niri fehlt";
        }

        function record(): string {
            return CaptureService.toggleRecording();
        }
    }

    IpcHandler {
        target: "procs"

        function toggle(): string {
            Runtime.procsOpen = !Runtime.procsOpen;
            return Runtime.procsOpen ? "offen" : "zu";
        }

        function top(): string {
            Procs.refresh();
            return Procs.shown.slice(0, 10).map(p => String(p.pid).padStart(7, " ") + "  " + p.cpu.toFixed(1).padStart(5, " ") + "%  " + p.name).join("\n");
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): string {
            Runtime.islandOpen = true;
            Runtime.clipOpen = !Runtime.clipOpen;
            return Runtime.clipOpen ? "offen" : "zu";
        }

        function list(): string {
            if (Clipboard.entries.length === 0)
                return "noch nichts kopiert";
            return Clipboard.entries.map((e, i) => (i + 1) + "  " + Clipboard.preview(e, 60)).join("\n");
        }

        function clear(): string {
            const n = Clipboard.entries.length;
            Clipboard.clear();
            return "geloescht: " + n;
        }
    }

    IpcHandler {
        target: "power"

        function menu(): string {
            Runtime.powerOpen = !Runtime.powerOpen;
            return Runtime.powerOpen ? "offen" : "zu";
        }

        // Einzeln aufrufbar, damit ein Tastenkuerzel direkt sperren kann.
        function lock(): string {
            Session.run("lock");
            return "gesperrt";
        }

        function logout(): string {
            Session.run("logout");
            return "abgemeldet";
        }

        function suspend(): string {
            Session.run("suspend");
            return "Bereitschaft";
        }
    }

    IpcHandler {
        target: "media"

        function playpause(): string {
            MediaService.playPause();
            return MediaService.playing ? "spielt" : "pausiert";
        }

        function next(): string {
            MediaService.next();
            return MediaService.label;
        }

        function previous(): string {
            MediaService.previous();
            return MediaService.label;
        }

        function status(): string {
            return JSON.stringify({
                "spielt": MediaService.playing,
                "titel": MediaService.title,
                "interpret": MediaService.artist,
                "player": MediaService.players.map(p => p.identity)
            });
        }
    }

    IpcHandler {
        target: "notify"

        function toggle(): string {
            Runtime.islandOpen = true;
            Runtime.notifyOpen = !Runtime.notifyOpen;
            return Runtime.notifyOpen ? "offen" : "zu";
        }

        // Der Server ist der Umschalter zwischen den beiden Shells -- deshalb
        // ein eigener Befehl und keine stille Automatik.
        function server(value: string): string {
            const next = value === "toggle" ? !Notify.enabled : (value === "on");
            Config.set("notifications", next);
            if (next)
                return "an — dms.service muss gestoppt sein, sonst haengt dessen Unit";
            return "aus — die Benachrichtigungen gehen wieder an DMS";
        }

        function dnd(): string {
            Notify.setDnd(!Notify.dnd);
            return Notify.dnd ? "nicht stoeren" : "wieder laut";
        }

        function clear(): string {
            const n = Notify.count;
            Notify.clear();
            return "geloescht: " + n;
        }

        function status(): string {
            return JSON.stringify({
                "server": Notify.enabled,
                "anzahl": Notify.count,
                "offene": Notify.popups.length,
                "dnd": Notify.dnd
            });
        }

        function list(): string {
            if (Notify.count === 0)
                return "nichts da";
            return Notify.history.map(e => (e.notification?.appName || "System") + ": " + (e.notification?.summary ?? "")).join("\n");
        }
    }

    IpcHandler {
        target: "tray"

        function list(): string {
            const items = SystemTray.items?.values ?? [];
            if (items.length === 0)
                return "leer";
            return items.map(i => (i.title || i.id) + (i.hasMenu ? "  [Menue]" : "")).join("\n");
        }
    }

    IpcHandler {
        target: "osd"

        // Zum Ausprobieren, ohne an einem Regler zu drehen.
        function test(): string {
            Osd.show("volume");
            return Osd.showing ? "sichtbar" : "unterdrueckt";
        }

        function on(): string {
            Config.set("osd", true);
            return "an";
        }

        function off(): string {
            Config.set("osd", false);
            return "aus";
        }

        function status(): string {
            return JSON.stringify({
                "an": Osd.enabled,
                "bereit": Osd.armed,
                "sichtbar": Osd.showing,
                "art": Osd.kind,
                "wert": Osd.value
            });
        }
    }

    IpcHandler {
        target: "launcher"

        function open(): string {
            Runtime.launcherOpen = true;
            return "offen";
        }

        function close(): string {
            Runtime.launcherOpen = false;
            return "zu";
        }

        function toggle(): string {
            Runtime.launcherOpen = !Runtime.launcherOpen;
            return Runtime.launcherOpen ? "offen" : "zu";
        }

        // Zum Pruefen ohne Tastatur -- und praktisch fuer Skripte.
        function find(query: string): string {
            return Apps.search(query).slice(0, 10).map(e => e.name).join("\n");
        }

        function count(): string {
            return String(Apps.entries.length);
        }
    }

    IpcHandler {
        target: "control"

        function toggle(): string {
            Runtime.islandOpen = true;
            Runtime.controlOpen = !Runtime.controlOpen;
            return Runtime.controlOpen ? "offen" : "zu";
        }

        function status(): string {
            return JSON.stringify({
                "netz": Net.summary,
                "online": Net.online,
                "wlan": Net.wifiEnabled,
                "netze": Net.wifiNetworks.length,
                "bluetooth": Bt.enabled,
                "verbunden": Bt.connected.map(d => Bt.label(d)),
                "helligkeit": Brightness.available ? Brightness.percent : -1
            });
        }
    }

    IpcHandler {
        target: "brightness"

        function up(): string {
            return String(Brightness.step(5));
        }

        function down(): string {
            return String(Brightness.step(-5));
        }

        function set(percent: string): string {
            return String(Brightness.set(parseInt(percent, 10)));
        }
    }

    IpcHandler {
        target: "audio"

        // Fuer die Multimediatasten: XF86AudioRaiseVolume -> `nbshell audio up`
        function up(): string {
            return String(Audio.step(5));
        }

        function down(): string {
            return String(Audio.step(-5));
        }

        function set(percent: string): string {
            return String(Audio.setVolume(parseInt(percent, 10)));
        }

        function mute(): string {
            Audio.toggleMute();
            return Audio.muted ? "stumm" : String(Audio.volume);
        }

        function micmute(): string {
            Audio.setMicMuted(!Audio.micMuted);
            return Audio.micMuted ? "stumm" : String(Audio.micVolume);
        }

        function panel(): string {
            Runtime.islandOpen = true;
            Runtime.audioPanelOpen = !Runtime.audioPanelOpen;
            return Runtime.audioPanelOpen ? "offen" : "zu";
        }

        function status(): string {
            return JSON.stringify({
                "volume": Audio.volume,
                "muted": Audio.muted,
                "sink": Audio.label(Audio.sink),
                "mic": Audio.micVolume,
                "micMuted": Audio.micMuted,
                "sinks": Audio.sinks.map(n => Audio.label(n))
            });
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
            return Runtime.wallpaperOpen ? "offen" : "zu";
        }

        function list(): string {
            // Die Liste wird sonst erst beim Oeffnen des Karussells gelesen --
            // beim ersten Aufruf hier waere sie leer.
            Wallpapers.refresh();
            if (Wallpapers.list.length === 0)
                return "noch nicht gelesen — Befehl gleich noch einmal aufrufen";
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
            Runtime.islandOpen = true;
            Runtime.themePickerOpen = true;
            return "offen";
        }

        function close(): string {
            Runtime.themePickerOpen = false;
            return "zu";
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
            return "neu gelesen";
        }
    }

    IpcHandler {
        target: "config"

        function get(key: string): string {
            return JSON.stringify(Config.value(key, null));
        }

        // Werte kommen als Text herein und werden, wenn moeglich, als JSON
        // gelesen -- so lassen sich auch Zahlen, Wahrheitswerte und Listen
        // setzen: `nbshell config set rightWidgets '["clock"]'`
        function set(key: string, value: string): string {
            var parsed = value;
            try {
                parsed = JSON.parse(value);
            } catch (e) {}
            Config.set(key, parsed);
            return key + " = " + JSON.stringify(parsed);
        }

        function dump(): string {
            return JSON.stringify(Config.data, null, 2);
        }
    }
}
