pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Befehle -- alles, was nbshell selbst kann, als durchsuchbare Liste.
//
// Der Gedanke stammt aus Omarchy 4: dort sind Anwendungsstarter und Menue zu
// EINER Flaeche verschmolzen, weil zwei Paletten mit zwei Tastenkuerzeln
// nichts trennen, was zusammengehoert. Vorher musste man wissen, dass das Theme
// hinter Mod+Comma steckt und die Aufgaben hinter Mod+T. Jetzt tippt man
// "theme" und drueckt Enter.
//
// Ausgefuehrt wird DIREKT, nicht ueber `nbshell …`: die Shell riefe sonst ein
// Programm auf, das ihr per IPC zurueckruft, um eine Property zu setzen, die
// sie selbst haelt -- dreimal um den Block fuer ein `= true`. Nur was nicht in
// der Shell liegt (Sitzung, Sperren), geht als Prozess hinaus.
//
// Was der Benutzer selbst dazuschreibt, steht in
// ~/.config/nbshell/commands.json und kann nur eine Befehlszeile mitbringen:
//
//   [ { "name": "Notizen", "comment": "Obsidian-Tresor", "run": "obsidian" } ]
Singleton {
    id: root

    // Ein Befehl sieht fuer den Starter aus wie eine Anwendung: `name` und
    // `comment` sind dieselben Felder, `kind` unterscheidet sie in der Zeile.
    // `act` ist die Tat; `confirm` verlangt ein zweites Enter.
    function entry(name, comment, category, act, confirm) {
        return {
            "kind": "cmd",
            "name": name,
            "comment": comment,
            "category": category,
            "act": act,
            "confirm": confirm === true
        };
    }

    property var userCommands: []

    readonly property var builtin: {
        const out = [];

        // ── Fenster ──────────────────────────────────────────────────────
        out.push(entry("Einstellungen", "Optionen der Shell", "Fenster", () => Runtime.settingsOpen = true));
        out.push(entry("Bausteine", "welche Zellen in der Leiste stehen", "Fenster", () => Runtime.modulesOpen = true));
        out.push(entry("Aufgaben", "die Liste (Mod+T)", "Fenster", () => Runtime.todoOpen = true));
        out.push(entry("Zwischenablage", "Verlauf (Mod+V)", "Fenster", () => Runtime.clipOpen = true));
        out.push(entry("Benachrichtigungen", "Archiv (Mod+N)", "Fenster", () => Runtime.notifyOpen = true));
        out.push(entry("Prozesse", "was laeuft und was frisst", "Fenster", () => Runtime.procsOpen = true));
        out.push(entry("Aufnahme", "Bildschirmfoto und Video", "Fenster", () => Runtime.captureOpen = true));
        out.push(entry("Hintergrundbild", "Karussell der Bilder (Mod+Y)", "Fenster", () => Runtime.wallpaperOpen = true));
        out.push(entry("Themewahl", "Farben durchblaettern", "Fenster", () => Runtime.themePickerOpen = true));
        out.push(entry("Sitzung", "Sperren, Abmelden, Ausschalten", "Fenster", () => Runtime.powerOpen = true));

        // ── Form der Leiste ──────────────────────────────────────────────
        out.push(entry("Leiste: Balken", "durchgehend ueber die Breite", "Form", () => Config.set("mode", "bar")));
        out.push(entry("Leiste: Insel", "freistehend, klappt zusammen", "Form", () => Config.set("mode", "island")));
        out.push(entry("Leiste: Pille", "freistehend, bleibt offen", "Form", () => Config.set("mode", "pill")));
        out.push(entry("Leiste nach oben", "Kante wechseln", "Form", () => Config.set("edge", "top")));
        out.push(entry("Leiste nach unten", "Kante wechseln", "Form", () => Config.set("edge", "bottom")));

        // ── Themes ───────────────────────────────────────────────────────
        // Jedes installierte Theme ist ein eigener Befehl: "gruv" und Enter
        // ist kuerzer als jede Liste, durch die man blaettert.
        out.push(entry("Theme: naechstes", "eins weiter", "Theme", () => ThemeIndex.step(1)));
        out.push(entry("Theme: voriges", "eins zurueck", "Theme", () => ThemeIndex.step(-1)));
        const themes = ThemeIndex.list;
        for (var i = 0; i < themes.length; i++) {
            const name = themes[i].name;
            out.push(entry("Theme: " + name, name === Config.theme ? "gerade aktiv" : "Farben wechseln", "Theme", () => ThemeIndex.apply(name)));
        }

        // Der Akzent als Rolle -- dieselbe Liste wie im Themewaehler, nur
        // ohne Maus. "akzent gelb" und Enter.
        const roles = Theme.accentRoles;
        for (var r = 0; r < roles.length; r++) {
            const role = roles[r];
            out.push(entry("Akzent: " + role, role === Theme.accentRole ? "gerade aktiv" : "Farbe aus der Palette des Themes", "Theme", () => Config.set("accent", role)));
        }

        // ── Dienste ──────────────────────────────────────────────────────
        out.push(entry(Notify.dnd ? "Nicht stoeren aus" : "Nicht stoeren an", "Karten unterdruecken", "Dienste", () => Notify.setDnd(!Notify.dnd)));
        out.push(entry(Audio.muted ? "Ton an" : "Ton aus", "Lautsprecher stumm schalten", "Dienste", () => Audio.toggleMute()));
        out.push(entry(Audio.micMuted ? "Mikrofon an" : "Mikrofon aus", "Aufnahme stumm schalten", "Dienste", () => Audio.setMicMuted(!Audio.micMuted)));
        out.push(entry("Updates pruefen", "Paketliste neu holen", "Dienste", () => Updates.refresh()));
        out.push(entry("Themeliste neu lesen", "nach neuen Themes suchen", "Dienste", () => ThemeIndex.refresh()));

        // ── Sitzung ──────────────────────────────────────────────────────
        // Was sich nicht zurueckdrehen laesst, fragt nach. In einer
        // Suchpalette liegt "Ausschalten" sonst einen Tippfehler entfernt.
        out.push(entry("Sperren", "Bildschirm sperren", "Sitzung", () => Session.run("lock")));
        out.push(entry("Bereitschaft", "suspend", "Sitzung", () => Session.run("suspend")));
        out.push(entry("Ruhezustand", "hibernate", "Sitzung", () => Session.run("hibernate"), true));
        out.push(entry("Abmelden", "niri beenden", "Sitzung", () => Session.run("logout"), true));
        out.push(entry("Neu starten", "reboot", "Sitzung", () => Session.run("reboot"), true));
        out.push(entry("Ausschalten", "poweroff", "Sitzung", () => Session.run("poweroff"), true));

        return out;
    }

    readonly property var all: root.builtin.concat(root.userCommands)

    // Gesucht wird in Name UND Beschreibung -- wer "stumm" tippt, meint den
    // Ton, auch wenn der Befehl "Ton aus" heisst. Die Beschreibung zaehlt
    // weniger, sonst draengt sich ein Eintrag wegen seines Fliesstexts vor.
    function rank(query) {
        const items = root.all;
        if (!query)
            return items.map(e => ({
                        "entry": e,
                        "points": 0
                    }));

        const list = [];
        for (var i = 0; i < items.length; i++) {
            const e = items[i];
            const points = Math.max(Apps.score(e.name, query), Apps.score(e.comment ?? "", query) * 0.4, Apps.score(e.category ?? "", query) * 0.5);
            if (points > 0)
                list.push({
                    "entry": e,
                    "points": points
                });
        }
        list.sort((a, b) => b.points - a.points || a.entry.name.localeCompare(b.entry.name));
        return list;
    }

    function search(query) {
        return rank(query).map(x => x.entry);
    }

    function invoke(command) {
        if (!command)
            return false;
        if (command.act) {
            command.act();
            return true;
        }
        if (command.run) {
            Apps.run(String(command.run));
            return true;
        }
        return false;
    }

    // Eigene Eintraege. Fehlt die Datei, ist das der Normalfall und kein
    // Fehler; ist sie kaputt, wird das gemeldet und die eingebauten bleiben --
    // ein Tippfehler darf die Palette nicht leeren.
    FileView {
        path: Config.configDir + "/commands.json"
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            var raw = [];
            try {
                raw = JSON.parse(text() || "[]");
            } catch (e) {
                console.warn("nbshell: commands.json ist kaputt —", e);
                return;
            }
            if (!Array.isArray(raw))
                return;
            root.userCommands = raw.filter(e => e && e.name && e.run).map(e => ({
                        "kind": "cmd",
                        "name": String(e.name),
                        "comment": String(e.comment ?? e.description ?? ""),
                        "category": String(e.category ?? "Eigene"),
                        "run": String(e.run),
                        "confirm": e.confirm === true
                    }));
        }
        onLoadFailed: root.userCommands = []
    }
}
