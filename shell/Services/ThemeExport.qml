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
    readonly property string umbrielPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/umbriel/nbshell-colors.toml"
    readonly property string palettePath: Config.configDir + "/palette.sh"
    readonly property string hookPath: Config.configDir + "/theme-hook.sh"
    readonly property string browserThemePath: Qt.resolvedUrl("../scripts/browser-theme.sh").toString().replace("file://", "")

    // Die 16 ANSI-Farben. Omarchys colors.toml hat genau diese Vorstellung von
    // Farbe -- deshalb ist das hier eine Zuordnung und keine Umrechnung.
    function palette16() {
        const c = Theme.c;
        return [c.background ?? "#000000", c.red ?? "#ff0000", c.green ?? "#00ff00", c.yellow ?? "#ffff00", c.blue ?? "#0000ff", c.magenta ?? "#ff00ff", c.cyan ?? "#00ffff", c.foreground ?? "#ffffff", c.dark_foreground ?? c.muted ?? "#808080", c.bright_red ?? c.red ?? "#ff0000", c.bright_green ?? c.green ?? "#00ff00", c.bright_yellow ?? c.yellow ?? "#ffff00", c.bright_blue ?? c.blue ?? "#0000ff", c.bright_magenta ?? c.magenta ?? "#ff00ff", c.bright_cyan ?? c.cyan ?? "#00ffff", c.bright_foreground ?? c.foreground ?? "#ffffff"];
    }

    // Dieselbe Palette als Datei, die eine Shell einlesen kann. Sie ist das
    // Angebot an `theme-hook.sh`: ohne sie muesste jeder Hook die colors.toml
    // selbst lesen -- und dabei BEIDE Dialekte beherrschen (benannte
    // Schluessel und color0…color15). Das ist hier schon passiert.
    function paletteShell() {
        const c = Theme.c;
        const p = palette16();
        const names = ["BLACK", "RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "WHITE", "BRIGHT_BLACK", "BRIGHT_RED", "BRIGHT_GREEN", "BRIGHT_YELLOW", "BRIGHT_BLUE", "BRIGHT_MAGENTA", "BRIGHT_CYAN", "BRIGHT_WHITE"];

        var out = "# Von nbshell geschrieben -- Theme: " + Config.theme + "\n";
        out += "# Do not edit manually; every theme change overwrites this file.\n";
        out += "# Gedacht zum Einlesen: . ~/.config/nbshell/palette.sh\n\n";
        out += "NB_THEME='" + Config.theme + "'\n";
        out += "NB_MODE='" + (Theme.isLight ? "light" : "dark") + "'\n\n";
        out += "NB_BG='" + (c.background ?? "#000000") + "'\n";
        out += "NB_BG_DARK='" + (c.dark_background ?? c.background ?? "#000000") + "'\n";
        out += "NB_BG_LIGHT='" + (c.lighter_background ?? c.background ?? "#000000") + "'\n";
        out += "NB_FG='" + (c.foreground ?? "#ffffff") + "'\n";
        out += "NB_FG_DIM='" + (c.dark_foreground ?? c.muted ?? "#808080") + "'\n";
        out += "NB_FG_BRIGHT='" + (c.bright_foreground ?? c.foreground ?? "#ffffff") + "'\n";
        // Der GEWAEHLTE Akzent, nicht der des Themes: wer die Leiste auf Gruen
        // stellt, will keinen blauen Cursor im Terminal und keinen blauen
        // Fensterrahmen daneben. `Theme.accent` loest die Rolle auf, und wenn
        // keine gesetzt ist, ist das genau der Vorschlag des Themes.
        out += "NB_ACCENT='" + Theme.accent + "'\n";
        out += "NB_ACCENT_ROLE='" + Theme.accentRole + "'\n";
        out += "NB_MUTED='" + (c.muted ?? "#808080") + "'\n";
        out += "NB_SELECTION='" + (c.selection ?? c.lighter_background ?? "#333333") + "'\n\n";
        for (var i = 0; i < p.length; i++)
            out += "NB_" + names[i] + "='" + p[i] + "'\n";
        out += "\n# Dieselben 16 in ANSI-Reihenfolge, fuer Schleifen.\n";
        out += "NB_ANSI=\"" + p.join(" ") + "\"\n";
        return out;
    }

    function ghosttyTheme() {
        const c = Theme.c;
        const p = palette16();

        var out = "# Von nbshell geschrieben -- Theme: " + Config.theme + "\n";
        out += "# Do not edit manually; every theme change overwrites this file.\n";
        for (var i = 0; i < p.length; i++)
            out += "palette = " + i + "=" + p[i] + "\n";
        out += "background = " + (c.background ?? "#000000") + "\n";
        out += "foreground = " + (c.foreground ?? "#ffffff") + "\n";
        out += "cursor-color = " + Theme.accent + "\n";
        out += "selection-background = " + (c.selection ?? c.lighter_background ?? "#333333") + "\n";
        out += "selection-foreground = " + (c.bright_foreground ?? c.foreground ?? "#ffffff") + "\n";
        return out;
    }

    // Fensterrahmen, Fokusring und Verwandte. niri liest das ueber einen
    // include; geschrieben wird dieselbe Form, die auch DMS benutzt -- nur
    // eben aus Omarchys Palette statt aus matugen.
    function niriColors() {
        const c = Theme.c;
        const active = String(Theme.accent);
        const inactive = c.muted ?? c.dark_foreground ?? "#555555";
        const urgent = c.red ?? "#ff0000";

        var out = "// Von nbshell geschrieben -- Theme: " + Config.theme + "\n";
        out += "// Do not edit manually; every theme change overwrites this file.\n\n";
        out += "layout {\n";
        out += "    focus-ring {\n        active-color \"" + active + "\"\n        inactive-color \"" + inactive + "\"\n        urgent-color \"" + urgent + "\"\n    }\n\n";
        out += "    border {\n        active-color \"" + active + "\"\n        inactive-color \"" + inactive + "\"\n        urgent-color \"" + urgent + "\"\n    }\n\n";
        out += "    tab-indicator {\n        active-color \"" + active + "\"\n        inactive-color \"" + inactive + "\"\n        urgent-color \"" + urgent + "\"\n    }\n\n";
        out += "    insert-hint {\n        color \"" + active + "80\"\n    }\n";
        out += "}\n";
        return out;
    }

    function umbrielColors() {
        const c = Theme.c;
        const active = String(Theme.accent);
        const inactive = c.muted ?? c.dark_foreground ?? "#555555";
        const warning = c.yellow ?? "#ffff00";
        const error = c.red ?? "#ff0000";
        const alpha = value => String(value).length === 7 ? String(value) + "FF" : String(value);
        const withAlpha = (value, opacity) => String(value).substring(0, 7) + opacity;
        var out = "# Generated by nbshell — theme: " + Config.theme + "\n";
        out += "# Include before nbshell.toml in ~/.config/umbriel/config.toml.\n\n";
        out += "[colors]\n";
        out += "background = \"" + alpha(c.background ?? "#000000") + "\"\n";
        out += "text_primary = \"" + alpha(c.foreground ?? "#ffffff") + "\"\n";
        out += "text_muted = \"" + alpha(inactive) + "\"\n";
        out += "accent_primary = \"" + alpha(active) + "\"\n";
        out += "accent_secondary = \"" + alpha(warning) + "\"\n";
        out += "warning = \"" + alpha(warning) + "\"\n";
        out += "error = \"" + alpha(error) + "\"\n\n";
        out += "[appearance]\n";
        out += "corner_radius = " + Number(Config.radius ?? 2) + "\n";
        out += "border_width = 2\nouter_border_width = 1\n";
        out += "border_focused = \"" + alpha(active) + "\"\n";
        out += "border_unfocused = \"" + alpha(inactive) + "\"\n";
        out += "outer_border_color = \"" + withAlpha(active, "80") + "\"\n";
        out += "insert_hint_color = \"" + withAlpha(active, "80") + "\"\n";
        out += "backdrop_color = \"" + alpha(c.background ?? "#000000") + "\"\n";
        return out;
    }

    function exportNow() {
        if (!enabled || Object.keys(Theme.c).length < 5)
            return;
        ghostty.setText(ghosttyTheme());
        niri.setText(niriColors());
        umbriel.setText(umbrielColors());
        palette.setText(paletteShell());
        // Das Skript bekommt Name und Modus mit, damit es nicht selbst in der
        // colors.toml nachsehen muss.
        hook.command = ["sh", "-c", "[ -x " + root.hookPath + " ] && exec " + root.hookPath + " " + Config.theme + " " + (Theme.isLight ? "light" : "dark") + " || true"];
        reloadTimer.restart();
    }

    // Ghostty liest seine Konfiguration nicht von selbst neu -- die frisch
    // geschriebene Themedatei saehe man erst im naechsten Fenster. Es hoert
    // aber auf SIGUSR2; das ist der vorgesehene Weg und im Programm auch so
    // protokolliert ("received SIGUSR2, reloading configuration").
    //
    // Ohne diesen Schritt schreibt die Shell eine Datei, die niemand liest --
    // und der Themewechsel hoert an der Fensterkante auf.
    //
    // Andere Terminals bringen ihr eigenes Nachladen mit (alacritty etwa
    // beobachtet seine Datei); alles Weitere gehoert in `theme-hook.sh`.
    Timer {
        id: reloadTimer

        // Kurz warten: die Dateien werden atomar geschrieben (schreiben,
        // umbenennen). Kommt das Signal davor an, liest Ghostty die alte
        // Fassung -- und der Hook laese eine palette.sh, die noch die vorige
        // Palette enthaelt. Beides haengt deshalb hier.
        interval: 200
        onTriggered: {
            reload.running = true;
            hook.running = true;
            browserTheme.running = true;
        }
    }

    Process {
        id: reload

        // `-x`: nur der Prozess, der genau so heisst. Ohne das traefe es auch
        // jede Shell, in deren Befehlszeile "ghostty" vorkommt.
        command: ["sh", "-c", "pkill -USR2 -x ghostty || true"]
    }

    // Nach jedem Themewechsel -- Theme.c wechselt, sobald die neue colors.toml
    // gelesen ist -- und nach jedem Wechsel der Akzentrolle: die Farbe der
    // Fensterrahmen und des Cursors haengt daran, das Theme aber nicht.
    Connections {
        target: Theme

        function onCChanged() {
            root.exportNow();
        }

        function onAccentRoleChanged() {
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

    FileView {
        id: umbriel
        path: root.umbrielPath
        watchChanges: false
        printErrors: true
        atomicWrites: true
    }

    FileView {
        id: palette
        path: root.palettePath
        atomicWrites: true
        printErrors: false
    }

    Process {
        id: hook
    }

    Process {
        id: browserTheme
        command: [root.browserThemePath, "apply"]
    }
}
