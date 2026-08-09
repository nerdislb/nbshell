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
import qs.Todo

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
        void Updates.enabled;
        void PowerService.available;
        void Calendar.enabled;
        void Plugins.scanned;
        void ThemeExport.enabled;
        // Die Aufgaben muessen von Anfang an gelesen werden, nicht erst beim
        // ersten Blick: sonst stuende in der Leiste eine 0, waehrend in der
        // Datei drei offene Punkte liegen -- und ein Abgleich vom Telefon
        // faende beim Schreiben eine leere eigene Seite vor.
        void Todo.count;
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

    TodoList {}

    // ── Steuerung von aussen ──────────────────────────────────────────────
    // Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell.

    IpcHandler {
        target: "bar"

        function mode(value: string): string {
            // `toggle` geht seit der Pille im Kreis statt hin und her. Ein
            // unbekannter Wert in der Config landet dabei auf "island" --
            // indexOf gibt -1, und -1 + 1 ist die erste Form.
            const order = ["island", "pill", "bar"];
            const next = value === "toggle" ? order[(order.indexOf(Config.mode) + 1) % order.length] : value;
            if (order.indexOf(next) < 0)
                return "unbekannt: " + value + " (island|pill|bar|toggle)";
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
                "aufgaben": Runtime.todoOpen,
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
        target: "updates"

        function check(): string {
            Updates.refresh();
            return "wird geprueft";
        }

        function list(): string {
            if (Updates.count === 0)
                return Updates.ready ? "alles aktuell" : "noch nicht geprueft";
            return Updates.repo.concat(Updates.aur).map(u => u.name + "  " + u.from + " -> " + u.to).join("\n");
        }

        function run(): string {
            Updates.update();
            return "Terminal geoeffnet";
        }

        function status(): string {
            return JSON.stringify({
                "anzahl": Updates.count,
                "repo": Updates.repo.length,
                "aur": Updates.aur.length,
                "prueft": Updates.checking,
                "befehl": Updates.updateCommand(),
                "terminal": Updates.terminal
            });
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
        target: "popout"

        // Klappt das Popout eines beliebigen Bausteins auf -- auch das eines
        // Plugins, das kein eigenes IPC-Ziel hat. Damit laesst sich jeder
        // Baustein auf eine Taste legen.
        function toggle(name: string): string {
            if (!Plugins.entry(name))
                return "unbekannter Baustein: " + name;
            Runtime.islandOpen = true;
            Runtime.requestPopout(name);
            return name;
        }
    }

    IpcHandler {
        target: "plugins"

        function list(): string {
            const rows = Plugins.catalog.map(e => {
                const kind = e.entry ? "plugin" : "eingebaut";
                return e.id.padEnd(16) + kind.padEnd(11) + e.name;
            });
            return rows.join("\n") + "\n\n" + Plugins.plugins.length + " von aussen — " + Plugins.dir;
        }

        function reload(): string {
            Plugins.refresh();
            return "wird neu eingelesen";
        }
    }

    IpcHandler {
        target: "calendar"

        function toggle(): string {
            Runtime.islandOpen = true;
            Runtime.calendarOpen = !Runtime.calendarOpen;
            return Runtime.calendarOpen ? "offen" : "zu";
        }

        // Was als Naechstes ansteht -- fuers Terminal, ohne Popout.
        function next(): string {
            const list = Calendar.upcoming(8);
            if (list.length === 0)
                return Calendar.available ? "nichts eingetragen" : ("Kalender nicht verfuegbar: " + Calendar.problem);
            return list.map(e => Qt.formatDateTime(e.start, "dd.MM") + "  " + (e.allDay ? "ganztags    " : Qt.formatDateTime(e.start, "HH:mm") + "       ") + e.title).join("\n");
        }

        function sync(): string {
            Calendar.sync();
            return "vdirsyncer angestossen";
        }

        function status(): string {
            return JSON.stringify({
                "verfuegbar": Calendar.available,
                "problem": Calendar.problem,
                "kalender": Calendar.calendars,
                "termine": Calendar.events.length,
                "fenster": Calendar.windowStart
            });
        }
    }

    IpcHandler {
        target: "todo"

        function toggle(): string {
            Runtime.todoOpen = !Runtime.todoOpen;
            return Runtime.todoOpen ? "offen" : "zu";
        }

        // Der Text kommt prozentkodiert herein -- Quickshells IPC-Aufrufer
        // zerlegt Kommas, Semikola und eckige Klammern zu eigenen Argumenten.
        // "Milch, Brot und Kaese" waeren sonst drei Argumente und der Aufruf
        // scheitert. `bin/nbshell` kodiert, hier steht es wieder her.
        function add(text: string): string {
            const clean = String(text).replace(/%5B/g, "[").replace(/%5D/g, "]").replace(/%2C/g, ",").replace(/%3B/g, ";").replace(/%25/g, "%");
            const entry = Todo.add(clean);
            return entry ? "eingetragen: " + entry.text : "leer -- nichts eingetragen";
        }

        function list(): string {
            if (Todo.list.length === 0)
                return "nichts vorgemerkt";
            return Todo.list.map((e, i) => String(i + 1).padStart(3, " ") + "  " + (e.done ? "[x]" : "[ ]") + "  " + e.text).join("\n");
        }

        // Nummern beziehen sich auf genau die Liste, die `list` ausgibt.
        function done(which: string): string {
            const e = Todo.list[parseInt(which, 10) - 1];
            if (!e)
                return "keine Nummer " + which;
            Todo.toggle(e.id);
            return (e.done ? "wieder offen: " : "erledigt: ") + e.text;
        }

        function drop(which: string): string {
            const e = Todo.list[parseInt(which, 10) - 1];
            if (!e)
                return "keine Nummer " + which;
            Todo.remove(e.id);
            return "geloescht: " + e.text;
        }

        function clear(): string {
            const n = Todo.clearDone();
            return n > 0 ? "aufgeraeumt: " + n : "nichts zu erledigen";
        }

        // Konfliktkopien einsammeln und die Datei neu lesen -- fuer den Fall,
        // dass der Abgleich lief, waehrend die Shell nicht hinsah.
        function sync(): string {
            Todo.foldConflicts();
            Todo.reload();
            return "gelesen: " + Todo.file;
        }

        function status(): string {
            return JSON.stringify({
                "an": Todo.enabled,
                "offen": Todo.count,
                "erledigt": Todo.doneCount,
                "gesamt": Todo.items.length,
                "datei": Todo.file,
                "grabsteine": Todo.keepDays
            });
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
        target: "battery"

        function status(): string {
            if (!PowerService.available)
                return "kein Akku";
            return JSON.stringify({
                "prozent": PowerService.percent,
                "zustand": PowerService.stateText,
                "restzeit": PowerService.timeText,
                "gesundheit": PowerService.health,
                "profil": PowerService.activeProfile
            });
        }

        function profile(name: string): string {
            if (!name)
                return PowerService.activeProfile;
            PowerService.setProfile(name);
            return name;
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
            return Notify.history.map(e => (e.appName || "System") + ": " + (e.summary ?? "")).join("\n");
        }
    }

    IpcHandler {
        target: "tray"

        function toggle(): string {
            const next = !Config.value("trayExpanded", false);
            Config.set("trayExpanded", next);
            return next ? "aufgeklappt" : "eingeklappt";
        }

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
            Runtime.launcherPrefill = "";
            Runtime.launcherOpen = !Runtime.launcherOpen;
            return Runtime.launcherOpen ? "offen" : "zu";
        }

        // Dieselbe Flaeche, nur mit gesetztem Praefix: ">" nur Befehle,
        // "!" nur Anwendungen.
        function palette(): string {
            Runtime.launcherPrefill = ">";
            Runtime.launcherOpen = true;
            return "offen";
        }

        function apps(): string {
            Runtime.launcherPrefill = "!";
            Runtime.launcherOpen = true;
            return "offen";
        }

        // Zum Pruefen ohne Tastatur -- und praktisch fuer Skripte. Zeigt
        // dieselbe Mischung aus Anwendungen und Befehlen wie das Fenster,
        // damit man die Reihenfolge nachsehen kann, ohne sie zu erraten.
        function find(query: string): string {
            const apps = Apps.rank(query);
            const cmds = Commands.rank(query).map(x => ({
                        "entry": x.entry,
                        "points": x.points * 0.9
                    }));
            const merged = query ? apps.concat(cmds).sort((a, b) => b.points - a.points) : apps.concat(cmds);
            return merged.slice(0, 10).map(x => (x.entry.kind === "cmd" ? "BEFEHL  " : "APP     ") + x.entry.name).join("\n");
        }

        // Einen Befehl ohne Fenster ausloesen -- fuer Skripte und zum Pruefen.
        // Was in der Palette nachfragt (Ausschalten, Abmelden), tut das hier
        // nicht: es lehnt ab. Ein Skript, das sich vertippt, soll nicht den
        // Rechner herunterfahren.
        function exec(query: string): string {
            const hit = Commands.search(query)[0];
            if (!hit)
                return "kein Befehl passt zu: " + query;
            if (hit.confirm)
                return hit.name + " fragt nach und geht nur im Fenster (Mod+Space)";
            Commands.invoke(hit);
            return hit.name;
        }

        function commands(query: string): string {
            return Commands.search(query).map(e => (e.category + "         ").substring(0, 9) + " " + e.name).join("\n");
        }

        function count(): string {
            return String(Apps.entries.length) + " Anwendungen, " + String(Commands.all.length) + " Befehle";
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
        // setzen: `nbshell set rightWidgets '["clock"]'`
        //
        // **Quickshells IPC-Aufrufer liest eckige Klammern als Argumentliste**
        // und zerlegt ausserdem an Kommas und Semikola. Aus `'["a","b"]'`
        // werden drei Argumente, und der Aufruf scheitert mit "2 required but
        // 3 were provided". Steuerzeichen helfen nicht -- 0x1F ist sein
        // eigenes Trennzeichen. `bin/nbshell` schickt die vier Zeichen deshalb
        // prozentkodiert; hier stehen sie wieder her.
        function set(key: string, value: string): string {
            var parsed = String(value).replace(/%5B/g, "[").replace(/%5D/g, "]").replace(/%2C/g, ",").replace(/%3B/g, ";").replace(/%25/g, "%");
            try {
                parsed = JSON.parse(parsed);
            } catch (e) {}
            Config.set(key, parsed);
            return key + " = " + JSON.stringify(parsed);
        }

        function dump(): string {
            return JSON.stringify(Config.data, null, 2);
        }
    }
}
