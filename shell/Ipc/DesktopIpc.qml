import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services

// Steuerung von aussen: Oberflaeche.
//
// Popouts, Einblendungen, Starter, Meldungen, Aufnahme.
//
// Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell. Diese Handler
// standen frueher alle in shell.qml -- 945 von 1088 Zeilen, sodass die
// eigentliche Frage "woraus besteht diese Shell?" unter der Fernsteuerung
// begraben lag. Sie sprechen ausschliesslich mit Singletons, also war der
// Schnitt schmerzlos.
Scope {
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

    // Das Menue (Mod+Shift+Space) -- der verschachtelte Sammelpunkt.
    IpcHandler {
        target: "menu"

        function toggle(): string {
            Runtime.menuOpen = !Runtime.menuOpen;
            return Runtime.menuOpen ? "offen" : "zu";
        }

        function open(): string {
            Runtime.menuOpen = true;
            return "offen";
        }

        function close(): string {
            Runtime.menuOpen = false;
            return "zu";
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

    // Die Tastenuebersicht (Mod+K).
    //
    // Nur das Fenster steht hier. Die LISTE holt `nbshell keys liste` direkt
    // aus scripts/keys.py -- sie liest niris Konfiguration und nicht den
    // Zustand der Shell, und soll deshalb auch antworten, wenn nbshell gar
    // nicht laeuft. Dieselbe Trennung wie bei der Mediathek.
    IpcHandler {
        target: "keys"

        function toggle(): string {
            Runtime.keysOpen = !Runtime.keysOpen;
            return Runtime.keysOpen ? "offen" : "zu";
        }

        function open(): string {
            Runtime.keysOpen = true;
            return "offen";
        }

        function reload(): string {
            Binds.load();
            return "liest neu";
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
}
