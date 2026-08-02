pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Gibt die Palette nach aussen weiter, damit ein Themewechsel nicht an der
// Leiste aufhoert.
//
// Bisher hat das matugen ueber DMS erledigt; ohne DMS faerbt sonst niemand
// mehr das Terminal mit. Geschrieben wird eine ghostty-Themedatei -- und
// danach ein eigenes Skript, falls es eines gibt: alles Weitere (btop, fuzzel,
// was auch immer) gehoert dorthin und nicht in die Shell.
Singleton {
    id: root

    readonly property bool enabled: Config.value("themeExport", true)

    readonly property string ghosttyPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ghostty/themes/nbcolors"
    readonly property string niriPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/niri/nbshell-colors.kdl"
    readonly property string hookPath: Config.configDir + "/theme-hook.sh"

    // ghostty will die 16 ANSI-Farben plus Hinter- und Vordergrund. Omarchys
    // colors.toml hat genau diese Vorstellung von Farbe -- deshalb ist das
    // hier eine Zuordnung und keine Umrechnung.
    function ghosttyTheme() {
        const c = Theme.c;
        const p = [c.background ?? "#000000", c.red ?? "#ff0000", c.green ?? "#00ff00", c.yellow ?? "#ffff00", c.blue ?? "#0000ff", c.magenta ?? "#ff00ff", c.cyan ?? "#00ffff", c.foreground ?? "#ffffff", c.dark_foreground ?? c.muted ?? "#808080", c.bright_red ?? c.red ?? "#ff0000", c.bright_green ?? c.green ?? "#00ff00", c.bright_yellow ?? c.yellow ?? "#ffff00", c.bright_blue ?? c.blue ?? "#0000ff", c.bright_magenta ?? c.magenta ?? "#ff00ff", c.bright_cyan ?? c.cyan ?? "#00ffff", c.bright_foreground ?? c.foreground ?? "#ffffff"];

        var out = "# Von nbshell geschrieben -- Theme: " + Config.theme + "\n";
        out += "# Nicht von Hand aendern, jeder Themewechsel ueberschreibt die Datei.\n";
        for (var i = 0; i < p.length; i++)
            out += "palette = " + i + "=" + p[i] + "\n";
        out += "background = " + (c.background ?? "#000000") + "\n";
        out += "foreground = " + (c.foreground ?? "#ffffff") + "\n";
        out += "cursor-color = " + (c.accent ?? c.foreground ?? "#ffffff") + "\n";
        out += "selection-background = " + (c.selection ?? c.lighter_background ?? "#333333") + "\n";
        out += "selection-foreground = " + (c.bright_foreground ?? c.foreground ?? "#ffffff") + "\n";
        return out;
    }

    // Fensterrahmen, Fokusring und Verwandte. niri liest das ueber einen
    // include; geschrieben wird dieselbe Form, die auch DMS benutzt -- nur
    // eben aus Omarchys Palette statt aus matugen.
    function niriColors() {
        const c = Theme.c;
        const active = c.accent ?? c.foreground ?? "#ffffff";
        const inactive = c.muted ?? c.dark_foreground ?? "#555555";
        const urgent = c.red ?? "#ff0000";

        var out = "// Von nbshell geschrieben -- Theme: " + Config.theme + "\n";
        out += "// Nicht von Hand aendern, jeder Themewechsel ueberschreibt die Datei.\n\n";
        out += "layout {\n";
        out += "    focus-ring {\n        active-color \"" + active + "\"\n        inactive-color \"" + inactive + "\"\n        urgent-color \"" + urgent + "\"\n    }\n\n";
        out += "    border {\n        active-color \"" + active + "\"\n        inactive-color \"" + inactive + "\"\n        urgent-color \"" + urgent + "\"\n    }\n\n";
        out += "    tab-indicator {\n        active-color \"" + active + "\"\n        inactive-color \"" + inactive + "\"\n        urgent-color \"" + urgent + "\"\n    }\n\n";
        out += "    insert-hint {\n        color \"" + active + "80\"\n    }\n";
        out += "}\n";
        return out;
    }

    function exportNow() {
        if (!enabled || Object.keys(Theme.c).length < 5)
            return;
        ghostty.setText(ghosttyTheme());
        niri.setText(niriColors());
        // Das Skript bekommt Name und Modus mit, damit es nicht selbst in der
        // colors.toml nachsehen muss.
        hook.command = ["sh", "-c", "[ -x " + root.hookPath + " ] && exec " + root.hookPath + " " + Config.theme + " " + (Theme.isLight ? "light" : "dark") + " || true"];
        hook.running = true;
    }

    // Nach jedem Themewechsel -- Theme.c wechselt, sobald die neue colors.toml
    // gelesen ist.
    Connections {
        target: Theme

        function onCChanged() {
            root.exportNow();
        }
    }

    FileView {
        id: ghostty
        path: root.ghosttyPath
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: niri
        path: root.niriPath
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: hook
    }
}
