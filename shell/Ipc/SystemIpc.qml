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
    // Die beiden Netzfenster.
    IpcHandler {
        target: "net"

        function qr(): string {
            Runtime.qrOpen = !Runtime.qrOpen;
            return Runtime.qrOpen ? "offen" : "zu";
        }

        function speed(): string {
            Runtime.speedOpen = !Runtime.speedOpen;
            return Runtime.speedOpen ? "offen" : "zu";
        }
    }

    // In der Naehe -- LocalSend ohne die App.
    IpcHandler {
        target: "nearby"

        function list(): string {
            if (Nearby.devices.length === 0)
                return Nearby.scanning ? "sucht …" : "niemand gefunden (erst `nbshell nearby scan`)";
            return Nearby.devices.map(d => (d.alias + "                    ").substring(0, 20) + d.ip + ":" + d.port + "  " + d.model).join("\n");
        }

        function scan(): string {
            Nearby.scan();
            return "sucht …";
        }

        // Ohne Zielangabe an das EINE gefundene Geraet -- gibt es mehrere,
        // muss man sich entscheiden. Wortlos das erste zu nehmen waere die
        // Sorte Hilfsbereitschaft, die Dateien an Fremde schickt.
        function send(file: string): string {
            if (Nearby.devices.length === 0)
                return "niemand gefunden -- erst `nbshell nearby scan`";
            if (Nearby.devices.length > 1)
                return "mehrere Geraete da:\n" + Nearby.devices.map(d => "  " + d.alias + "  (" + d.ip + ")").join("\n") + "\nZiel angeben: nbshell nearby send <datei> <alias>";
            Nearby.sendFiles(Nearby.devices[0], [file]);
            return "sendet an " + Nearby.devices[0].alias;
        }

        function sendTo(file: string, alias: string): string {
            const ziel = Nearby.devices.find(d => d.alias === alias || d.ip === alias);
            if (!ziel)
                return "nicht gefunden: " + alias;
            Nearby.sendFiles(ziel, [file]);
            return "sendet an " + ziel.alias;
        }

        function status(): string {
            return JSON.stringify({
                "geraete": Nearby.devices.length,
                "sucht": Nearby.scanning,
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
                "insel": Runtime.islandOpen,
                "starter": Runtime.launcherOpen,
                "einstellungen": Runtime.settingsOpen,
                "bausteine": Runtime.modulesOpen,
                "hintergrund": Runtime.wallpaperOpen,
                "aufgaben": Runtime.todoOpen,
                "qr": Runtime.qrOpen,
                "speedtest": Runtime.speedOpen,
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
            return Updates.repo.concat(Updates.aur).concat(Updates.flatpak).map(u => u.name + "  " + (u.from === u.to ? u.to + " (neuer Build)" : u.from + " -> " + u.to)).join("\n");
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
                "flatpak": Updates.flatpak.length,
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
            Runtime.pluginDeveloperOpen = !Runtime.pluginDeveloperOpen;
            return Runtime.pluginDeveloperOpen ? "offen" : "zu";
        }

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
