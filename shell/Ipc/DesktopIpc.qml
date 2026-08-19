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
        target: "dashboard"
        function toggle(): string { Runtime.dashboardOpen = !Runtime.dashboardOpen; return Runtime.dashboardOpen ? "open" : "closed"; }
        function open(): string { Runtime.dashboardOpen = true; return "open"; }
        function close(): string { Runtime.dashboardOpen = false; return "closed"; }
        function view(page: string): string {
            const names = ["today", "media", "tools"];
            const aliases = ({ "heute": 0, "medien": 1, "werkzeuge": 2 });
            const requested = String(page).toLowerCase();
            let index = names.indexOf(requested);
            if (index < 0 && aliases[requested] !== undefined)
                index = aliases[requested];
            if (index < 0)
                return "today | media | tools";
            Runtime.dashboardPage = index;
            Runtime.dashboardOpen = true;
            return names[index];
        }
    }

    IpcHandler {
        target: "hub"
        function toggle(): string { Runtime.hubOpen = !Runtime.hubOpen; return Runtime.hubOpen ? "open" : "closed"; }
        function open(): string { Runtime.hubOpen = true; return "open"; }
        function close(): string { Runtime.hubOpen = false; return "closed"; }
    }

    IpcHandler {
        target: "emoji"
        function toggle(): string { Runtime.emojiOpen = !Runtime.emojiOpen; return Runtime.emojiOpen ? "open" : "closed"; }
        function open(): string { Runtime.emojiOpen = true; return "open"; }
        function close(): string { Runtime.emojiOpen = false; return "closed"; }
    }

    IpcHandler {
        target: "plugin"

        function open(id: string): string {
            return Plugins.invoke(id, "open", "{}");
        }

        function close(id: string): string {
            return Plugins.invoke(id, "close", "{}");
        }

        function toggle(id: string): string {
            return Plugins.invoke(id, "toggle", "{}");
        }
    }

    IpcHandler {
        target: "capture"

        function menu(): string {
            Runtime.captureOpen = !Runtime.captureOpen;
            return Runtime.captureOpen ? "open" : "closed";
        }

        function screen(): string {
            return CaptureService.shoot("screen") ? "Screen" : "niri missing";
        }

        function window(): string {
            return CaptureService.shoot("window") ? "Window" : "niri missing";
        }

        function region(): string {
            return CaptureService.shoot("region") ? "Bereich" : "niri missing";
        }

        function ocr(): string {
            return CaptureService.ocr() ? "Texterkennung" : "niri missing";
        }

        function qr(): string {
            return CaptureService.qr() ? "QR-Erkennung" : "niri missing";
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
            return Runtime.menuOpen ? "open" : "closed";
        }

        function open(): string {
            Runtime.menuOpen = true;
            return "open";
        }

        function close(): string {
            Runtime.menuOpen = false;
            return "closed";
        }
    }

    IpcHandler {
        target: "procs"

        function toggle(): string {
            Runtime.procsOpen = !Runtime.procsOpen;
            return Runtime.procsOpen ? "open" : "closed";
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
            return Runtime.keysOpen ? "open" : "closed";
        }

        function open(): string {
            Runtime.keysOpen = true;
            return "open";
        }

        function reload(): string {
            Binds.load();
            return "reloading";
        }
    }

    IpcHandler {
        target: "popout"

        // Klappt das Popout eines beliebigen Bausteins auf -- auch das eines
        // Plugins, das kein eigenes IPC-Ziel hat. Damit laesst sich jeder
        // Baustein auf eine Taste legen.
        function toggle(name: string): string {
            if (!Plugins.entry(name))
                return "unknown module: " + name;
            Runtime.revealIslandTemporarily();
            Runtime.requestPopout(name);
            return name;
        }
    }

    IpcHandler {
        target: "notify"

        function center(): string {
            Runtime.notificationCenterOpen = !Runtime.notificationCenterOpen;
            return Runtime.notificationCenterOpen ? "open" : "closed";
        }

        function toggle(): string {
            Runtime.revealIslandTemporarily();
            Runtime.notifyOpen = !Runtime.notifyOpen;
            return Runtime.notifyOpen ? "open" : "closed";
        }

        // Der Server ist der Umschalter zwischen den beiden Shells -- deshalb
        // ein eigener Befehl und keine stille Automatik.
        function server(value: string): string {
            if (value === "status")
                return Notify.enabled ? "on — nbshell provides the notification service" : "off — notifications are handled elsewhere";
            const next = value === "toggle" ? !Notify.enabled : (value === "on");
            Config.set("notifications", next);
            if (next)
                return "on — nbshell provides the notification service";
            return "off — notifications are handled elsewhere";
        }

        function dnd(): string {
            Notify.setDnd(!Notify.dnd);
            return Notify.dnd ? "do not disturb" : "notifications enabled";
        }

        function clear(): string {
            const n = Notify.count;
            Notify.clear();
            return "cleared: " + n;
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
                return "nothing here";
            return Notify.history.map(e => (e.appName || "System") + ": " + (e.summary ?? "")).join("\n");
        }
    }

    IpcHandler {
        target: "tray"

        function toggle(): string {
            const next = !Config.value("trayExpanded", false);
            Config.set("trayExpanded", next);
            return next ? "expanded" : "collapsed";
        }

        function list(): string {
            const items = SystemTray.items?.values ?? [];
            if (items.length === 0)
                return "empty";
            return items.map(i => (i.title || i.id) + (i.hasMenu ? "  menu" : "")).join("\n");
        }
    }

    IpcHandler {
        target: "osd"

        // Zum Ausprobieren, ohne an einem Regler zu drehen.
        function test(): string {
            Osd.show("volume");
            return Osd.showing ? "visible" : "suppressed";
        }

        function on(): string {
            Config.set("osd", true);
            return "on";
        }

        function off(): string {
            Config.set("osd", false);
            return "off";
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
            return "open";
        }

        function close(): string {
            Runtime.launcherOpen = false;
            return "closed";
        }

        function toggle(): string {
            Runtime.launcherPrefill = "";
            Runtime.launcherOpen = !Runtime.launcherOpen;
            return Runtime.launcherOpen ? "open" : "closed";
        }

        // Dieselbe Flaeche, nur mit gesetztem Praefix: ">" nur Befehle,
        // "!" nur Anwendungen.
        function palette(): string {
            Runtime.launcherPrefill = ">";
            Runtime.launcherOpen = true;
            return "open";
        }

        function apps(): string {
            Runtime.launcherPrefill = "!";
            Runtime.launcherOpen = true;
            return "open";
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
                return "no command matches: " + query;
            if (hit.confirm)
                return hit.name + " requires confirmation and only runs in the window (Mod+Space)";
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
            Runtime.revealIslandTemporarily();
            Runtime.controlOpen = !Runtime.controlOpen;
            return Runtime.controlOpen ? "open" : "closed";
        }

        function status(): string {
            return JSON.stringify({
                "netz": Net.summary,
                "online": Net.online,
                "wlan": Net.wifiEnabled,
                "netze": Net.wifiNetworks.length,
                "bluetooth": Bt.enabled,
                "connected": Bt.connected.map(d => Bt.label(d)),
                "brightness": Brightness.available ? Brightness.percent : -1
            });
        }
    }
}
