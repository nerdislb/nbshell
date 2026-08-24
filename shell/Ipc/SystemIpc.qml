import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services

// Steuerung von aussen: System.
//
// Zustand, Einstellungen, Netz, Aktualisierungen, Erweiterungen.
//
// Aufrufbar als `nbshell <ziel> <befehl>`, siehe bin/nbshell. Diese Handler
// standen frueher alle in shell.qml -- 945 von 1088 Zeilen, sodass die
// eigentliche Frage "woraus besteht diese Shell?" unter der Fernsteuerung
// begraben lag. Sie sprechen ausschliesslich mit Singletons, also war der
// Schnitt schmerzlos.
Scope {
    IpcHandler {
        target: "displays"
        function toggle(): string { Runtime.displayOpen = !Runtime.displayOpen; return Runtime.displayOpen ? "open" : "closed"; }
        function open(): string { Runtime.displayOpen = true; return "open"; }
        function close(): string { Runtime.displayOpen = false; return "closed"; }
        function refresh(): string { Displays.refresh(); return "refreshing"; }
    }

    IpcHandler {
        target: "uiGallery"
        function toggle(): string { Runtime.uiGalleryOpen = !Runtime.uiGalleryOpen; return Runtime.uiGalleryOpen ? "open" : "closed"; }
        function open(): string { Runtime.uiGalleryOpen = true; return "open"; }
        function close(): string { Runtime.uiGalleryOpen = false; return "closed"; }
    }

    // Die beiden Netzfenster.
    IpcHandler {
        target: "net"

        function qr(): string {
            Runtime.qrOpen = !Runtime.qrOpen;
            return Runtime.qrOpen ? "open" : "closed";
        }

        function speed(): string {
            Runtime.speedOpen = !Runtime.speedOpen;
            return Runtime.speedOpen ? "open" : "closed";
        }
    }

    // In der Naehe -- LocalSend ohne die App.
    IpcHandler {
        target: "nearby"

        function list(): string {
            if (Nearby.devices.length === 0)
                return Nearby.scanning ? "scanning …" : "no devices found (run `nbshell nearby scan` first)";
            return Nearby.devices.map(d => (d.alias + "                    ").substring(0, 20) + d.ip + ":" + d.port + "  " + d.model).join("\n");
        }

        function scan(): string {
            Nearby.scan();
            return "scanning …";
        }

        // Ohne Zielangabe an das EINE gefundene Geraet -- gibt es mehrere,
        // muss man sich entscheiden. Wortlos das erste zu nehmen waere die
        // Sorte Hilfsbereitschaft, die Dateien an Fremde schickt.
        function send(file: string): string {
            if (Nearby.devices.length === 0)
                return "no devices found -- run `nbshell nearby scan` first";
            if (Nearby.devices.length > 1)
                return "multiple devices found:\n" + Nearby.devices.map(d => "  " + d.alias + "  (" + d.ip + ")").join("\n") + "\nChoose a target: nbshell nearby send <file> <alias>";
            Nearby.sendFiles(Nearby.devices[0], [file]);
            return "sending to " + Nearby.devices[0].alias;
        }

        function sendTo(file: string, alias: string): string {
            const ziel = Nearby.devices.find(d => d.alias === alias || d.ip === alias);
            if (!ziel)
                return "not found: " + alias;
            Nearby.sendFiles(ziel, [file]);
            return "sending to " + ziel.alias;
        }

        function status(): string {
            return JSON.stringify({
                "geraete": Nearby.devices.length,
                "scanning": Nearby.scanning,
                "sendet": Nearby.sending,
                "meldung": Nearby.status
            });
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
                "island": Runtime.islandOpen,
                "launcher": Runtime.launcherOpen,
                "settings": Runtime.settingsOpen,
                "modules": Runtime.modulesOpen,
                "wallpaper": Runtime.wallpaperOpen,
                "tasks": Runtime.todoOpen,
                "qr": Runtime.qrOpen,
                "speedtest": Runtime.speedOpen,
                "processes": Runtime.procsOpen,
                "capture": Runtime.captureOpen,
                "power": Runtime.powerOpen,
                "displays": Runtime.displayOpen,
                "uiGallery": Runtime.uiGalleryOpen
            });
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): string {
            Runtime.settingsOpen = !Runtime.settingsOpen;
            return Runtime.settingsOpen ? "open" : "closed";
        }

        function modules(): string {
            Runtime.modulesOpen = !Runtime.modulesOpen;
            return Runtime.modulesOpen ? "open" : "closed";
        }
    }

    IpcHandler {
        target: "updates"

        function check(): string {
            Updates.refresh();
            return "checking";
        }

        function list(): string {
            if (Updates.count === 0)
                return Updates.ready ? "everything is up to date" : "not checked yet";
            return Updates.repo.concat(Updates.aur).concat(Updates.flatpak).map(u => u.name + "  " + (u.from === u.to ? u.to + " (new build)" : u.from + " -> " + u.to)).join("\n");
        }

        function run(): string {
            Updates.update();
            return "terminal opened";
        }

        function status(): string {
            return JSON.stringify({
                "count": Updates.count,
                "repo": Updates.repo.length,
                "aur": Updates.aur.length,
                "flatpak": Updates.flatpak.length,
                "checking": Updates.checking,
                "rebootRecommended": Updates.rebootRecommended,
                "rebootPackages": Updates.rebootPackages,
                "command": Updates.updateCommand(),
                "terminal": Updates.terminal
            });
        }
    }

    IpcHandler {
        target: "shellUpdate"

        function check(): string {
            ShellUpdates.refresh();
            return "checking published releases";
        }

        function install(): string {
            ShellUpdates.install();
            return "terminal opened";
        }

        function installCompositor(): string {
            ShellUpdates.installCompositor();
            return "terminal opened";
        }

        function installAll(): string {
            ShellUpdates.installAll();
            return "terminal opened";
        }

        function notes(): string {
            ShellUpdates.openNotes();
            return ShellUpdates.releaseUrl !== "" ? "release notes opened" : "no release available";
        }

        function status(): string {
            return JSON.stringify({
                "channel": ShellUpdates.channel,
                "current": ShellUpdates.current,
                "latest": ShellUpdates.latest,
                "available": ShellUpdates.updateAvailable,
                "installable": ShellUpdates.installable,
                "checking": ShellUpdates.checking,
                "error": ShellUpdates.error,
                "url": ShellUpdates.releaseUrl,
                "umbriel": {
                    "installed": ShellUpdates.compositorInstalled,
                    "available": ShellUpdates.compositorUpdateAvailable,
                    "installable": ShellUpdates.compositorInstallable,
                    "checking": ShellUpdates.compositorChecking,
                    "error": ShellUpdates.compositorError,
                    "projects": ShellUpdates.compositorProjects
                }
            });
        }
    }

    IpcHandler {
        target: "ai"

        function status(): string {
            if (!AiUsage.available)
                return "helper script not found";
            if (AiUsage.list.length === 0)
                return "no data yet";
            return AiUsage.list.map(e => {
                const time = AiUsage.untilReset(e);
                var s = e.id + "  " + e.percent + "%";
                if (e.window !== "")
                    s += "  " + e.window;
                if (time !== "")
                    s += (e.window !== "" ? ", " : "  ") + time;
                return s;
            }).join("\n");
        }

        function refresh(): string {
            AiUsage.refresh();
            return "abgerufen";
        }
    }

    IpcHandler {
        target: "plugins"

        function developer(): string {
            Runtime.pluginManagerTab = "installed";
            Runtime.pluginDeveloperOpen = !Runtime.pluginDeveloperOpen;
            return Runtime.pluginDeveloperOpen ? "open" : "closed";
        }

        function store(): string {
            Runtime.pluginManagerTab = "store";
            Runtime.pluginDeveloperOpen = true;
            return "open";
        }

        function list(): string {
            const idWidth = Math.max(16, ...Plugins.catalog.map(e => e.id.length + 2));
            const rows = Plugins.catalog.map(e => {
                const kind = e.entry ? "plugin" : "built-in";
                return e.id.padEnd(idWidth) + kind.padEnd(11) + e.name;
            });
            return rows.join("\n") + "\n\n" + Plugins.plugins.length + " external — " + Plugins.dir;
        }

        function reload(): string {
            Plugins.refresh();
            return "reloading";
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
