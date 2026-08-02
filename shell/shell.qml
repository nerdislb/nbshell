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
    }

    Bar {}

    Wallpaper {}

    Launcher {}

    Osd {}

    Popups {}

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
            Config.set("theme", name);
            return name;
        }

        function current(): string {
            return Config.theme;
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
