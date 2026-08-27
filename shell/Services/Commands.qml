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
// hinter Mod+Comma steckt und die Tasks hinter Mod+T. Jetzt tippt man
// "theme" und drueckt Enter.
//
// Ausgefuehrt wird DIREKT, nicht ueber `nbshell …`: die Shell riefe sonst ein
// Programm auf, das ihr per IPC zurueckruft, um eine Property zu setzen, die
// sie selbst haelt -- dreimal um den Block fuer ein `= true`. Nur was nicht in
// der Shell liegt (Session, Lock), geht als Prozess hinaus.
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

        // ── Windows ──────────────────────────────────────────────────────
        out.push(entry("Settings", "Shell options", "Windows", () => Runtime.settingsOpen = true));
        out.push(entry("Main menu", "Command center (Mod+Space)", "Windows", () => Runtime.openMenu()));
        out.push(entry("System & Plugins", "Herdr, sync, updates, printing, ports, and hardware (Mod+Ctrl+H)", "Windows", () => Runtime.hubOpen = true));
        out.push(entry("Modules", "choose the modules shown in the bar", "Windows", () => Runtime.modulesOpen = true));
        out.push(entry("Emoji", "search and copy (Mod+Ctrl+E)", "Windows", () => Runtime.emojiOpen = true));
        out.push(entry("Audio", "devices and application volumes (Mod+Ctrl+A)", "Windows", () => Runtime.audioPanelOpen = true));
        out.push(entry("Tasks", "task list (Mod+T)", "Windows", () => Runtime.todoOpen = true));
        out.push(entry("Restore audio", "move headphones back to the laptop", "Audio", () => Audio.tonZurueck()));
        out.push(entry("Clipboard", "history (Mod+V)", "Windows", () => Runtime.clipOpen = true));
        out.push(entry("Notifications", "archive (Mod+N)", "Windows", () => Runtime.notifyOpen = true));
        out.push(entry("Processes", "running processes and resource usage", "Windows", () => Runtime.procsOpen = true));
        out.push(entry("Capture", "screenshots and video", "Windows", () => Runtime.captureOpen = true));
        out.push(entry("Demo recording", "record and export a short desktop showcase", "Windows", () => Apps.run("nbshell demo start region")));
        out.push(entry("Wallpaper", "browse wallpapers (Mod+Y)", "Windows", () => Runtime.wallpaperOpen = true));
        out.push(entry("Theme picker", "browse colors", "Windows", () => Runtime.themePickerOpen = true));
        out.push(entry("Library", "themes, wallpapers, and reviewed plugins", "Windows", () => Runtime.storeOpen = true));
        out.push(entry("Session", "lock, log out, power off", "Windows", () => Runtime.powerOpen = true));

        // ── Form der Leiste ──────────────────────────────────────────────
        out.push(entry("Bar: full width", "spans the entire screen width", "Shape", () => Config.set("mode", "bar")));
        out.push(entry("Bar: island", "floating and collapsible", "Shape", () => Config.set("mode", "island")));
        out.push(entry("Bar: pill", "floating and always expanded", "Shape", () => Config.set("mode", "pill")));
        out.push(entry("Move bar to top", "change screen edge", "Shape", () => Config.set("edge", "top")));
        out.push(entry("Move bar to bottom", "change screen edge", "Shape", () => Config.set("edge", "bottom")));

        // ── Themes ───────────────────────────────────────────────────────
        // Jedes installierte Theme ist ein eigener Befehl: "gruv" und Enter
        // ist kuerzer als jede Liste, durch die man blaettert.
        out.push(entry("Theme: next", "next", "Theme", () => ThemeIndex.step(1)));
        out.push(entry("Theme: previous", "previous", "Theme", () => ThemeIndex.step(-1)));
        const themes = ThemeIndex.list;
        for (var i = 0; i < themes.length; i++) {
            const name = themes[i].name;
            out.push(entry("Theme: " + name, name === Config.theme ? "currently active" : "change colors", "Theme", () => ThemeIndex.apply(name)));
        }

        // Der Akzent als Rolle -- dieselbe Liste wie im Themewaehler, nur
        // ohne Maus. "akzent gelb" und Enter.
        const roles = Theme.accentRoles;
        for (var r = 0; r < roles.length; r++) {
            const role = roles[r];
            out.push(entry("Accent: " + role, role === Theme.accentRole ? "currently active" : "color from the theme palette", "Theme", () => Config.set("accent", role)));
        }

        // ── Services ──────────────────────────────────────────────────────
        out.push(entry(Notify.dnd ? "Disable do not disturb" : "Enable do not disturb", "suppress notification cards", "Services", () => Notify.setDnd(!Notify.dnd)));
        out.push(entry(Audio.muted ? "Unmute audio" : "Mute audio", "mute the speakers", "Services", () => Audio.toggleMute()));
        out.push(entry(Audio.micMuted ? "Unmute microphone" : "Mute microphone", "mute audio capture", "Services", () => Audio.setMicMuted(!Audio.micMuted)));
        out.push(entry("Check for updates", "refresh package list", "Services", () => Updates.refresh()));
        out.push(entry(Idle.caffeine ? "Disable keep awake" : "Enable keep awake", "prevent dimming, screen-off, and locking", "Services", () => Idle.toggleCaffeine()));
        out.push(entry(Idle.enabled ? "Disable idle automation" : "Enable idle automation", "dim, turn off, and lock", "Services", () => Config.set("idle", !Idle.enabled)));
        out.push(entry("Reload theme list", "look for new themes", "Services", () => ThemeIndex.refresh()));

        // ── Security ──────────────────────────────────────────────────────
        // Delegate all password handling to 1Password. nbshell only starts
        // the vendor-provided UI and never reads vault or clipboard data.
        out.push(entry("Approve next system action", "one sudo or Polkit request via paired phone", "Security", () => Quickshell.execDetached([Apps.terminal, "-e", "sh", "-lc", "nbshell auth approve-next system; printf '\\nEnter closes this window … '; read -r _"])));
        out.push(entry("Open 1Password", "password manager", "Security", () => Apps.run("1password --show")));
        out.push(entry("1Password Quick Access", "search passwords (Ctrl+Shift+Space)", "Security", () => Apps.run("1password --quick-access")));
        out.push(entry("Lock 1Password", "lock the password manager", "Security", () => Apps.run("1password --lock")));

        // ── Session ──────────────────────────────────────────────────────
        // Was sich nicht zurueckdrehen laesst, fragt nach. In einer
        // Suchpalette liegt "Power off" sonst einen Tippfehler entfernt.
        out.push(entry("Lock", "lock the screen", "Session", () => Session.run("lock")));
        out.push(entry("Suspend", "suspend", "Session", () => Session.run("suspend")));
        out.push(entry("Hibernate", "hibernate", "Session", () => Session.run("hibernate"), true));
        out.push(entry("Log out", "quit niri", "Session", () => Session.run("logout"), true));
        out.push(entry("Restart", "reboot", "Session", () => Session.run("reboot"), true));
        out.push(entry("Power off", "poweroff", "Session", () => Session.run("poweroff"), true));

        return out;
    }

    readonly property var all: root.builtin.concat(root.userCommands)

    // Gesucht wird in Name UND Beschreibung -- wer "stumm" tippt, meint den
    // Audio, auch wenn der Befehl "Audio aus" heisst. Die Beschreibung zaehlt
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
                        "category": String(e.category ?? "Custom"),
                        "run": String(e.run),
                        "confirm": e.confirm === true
                    }));
        }
        onLoadFailed: root.userCommands = []
    }
}
