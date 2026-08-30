#!/usr/bin/env python3
"""Alle Tastenkuerzel von niri, als JSON.

Warum ein Parser und keine Abfrage: niri gibt seine Bindungen nicht ueber IPC
heraus (`niri msg` kennt Ausgaenge, Fenster, Arbeitsflaechen -- keine Tasten).
Die einzige Quelle ist die Konfiguration selbst.

Die drei Dinge, die dabei zaehlen:

  * `include` verfolgen. Diese Konfiguration steht in acht Dateien -- die von
    DMS, die eigenen Overrides, die Uebernahme durch nbshell. Wer nur
    config.kdl liest, findet die Haelfte.
  * Die REIHENFOLGE einhalten. In niri gewinnt die zuletzt gelesene Bindung.
    my-binds.kdl biegt Mod+Return von alacritty auf ghostty um; steht in der
    Liste beides, ist sie falsch. Deshalb wird zuletzt gewonnene Bindung
    behalten, und zwar an der Stelle, an der die Taste zuerst auftauchte --
    sonst springt die Liste bei jeder Aenderung durcheinander.
  * Eine Beschreibung, die man lesen kann. `hotkey-overlay-title` ist die beste
    Quelle, weil sie ein Mensch geschrieben hat. Fehlt sie, wird die Aktion
    uebersetzt -- `focus-column-left` sagt niemandem etwas, "eine Spalte nach
    links" schon.
"""

import json
import os
import re
import sys
import tomllib

KONFIG = os.path.expanduser(
    os.environ.get("NBSHELL_NIRI_CONFIG", "~/.config/niri/config.kdl")
)
UMBRIEL_KONFIG = os.path.expanduser(
    os.environ.get("NBSHELL_UMBRIEL_CONFIG", "~/.config/umbriel/nbshell.toml")
)

# Was die Aktionen bedeuten. Nur die, die niri wirklich hat -- ein Eintrag, den
# niemand benutzt, kostet nichts, ein falscher kostet Vertrauen.
AKTIONEN = {
    "close-window": "close window",
    "fullscreen-window": "fullscreen",
    "toggle-windowed-fullscreen": "windowed fullscreen",
    "maximize-column": "maximize/restore column",
    "center-column": "center column",
    "center-visible-columns": "center visible columns",
    "consume-or-expel-window-left": "move window into/out of left column",
    "consume-or-expel-window-right": "move window into/out of right column",
    "consume-window-into-column": "move window into column",
    "expel-window-from-column": "move window out of column",
    "switch-preset-column-width": "cycle column width",
    "switch-preset-window-height": "cycle window height",
    "reset-window-height": "reset window height",
    "toggle-window-floating": "toggle floating",
    "switch-focus-between-floating-and-tiling": "switch floating/tiling focus",
    "toggle-column-tabbed-display": "toggle tabbed column",
    "toggle-overview": "overview",
    "focus-column-left": "focus column left",
    "focus-column-right": "focus column right",
    "focus-column-first": "focus first column",
    "focus-column-last": "focus last column",
    "focus-window-up": "focus window above",
    "focus-window-down": "focus window below",
    "focus-window-or-workspace-up": "focus window or workspace above",
    "focus-window-or-workspace-down": "focus window or workspace below",
    "move-column-left": "move column left",
    "move-column-right": "move column right",
    "move-column-to-first": "move column to start",
    "move-column-to-last": "move column to end",
    "move-window-up": "move window up",
    "move-window-down": "move window down",
    "move-window-up-or-to-workspace-up": "move window or workspace up",
    "move-window-down-or-to-workspace-down": "move window or workspace down",
    "focus-workspace-up": "workspace up",
    "focus-workspace-down": "workspace down",
    "focus-workspace-previous": "previous workspace",
    "move-column-to-workspace-up": "move column one workspace up",
    "move-column-to-workspace-down": "move column one workspace down",
    "move-workspace-up": "move workspace up",
    "move-workspace-down": "move workspace down",
    "focus-monitor-left": "focus display left",
    "focus-monitor-right": "focus display right",
    "focus-monitor-up": "focus display above",
    "focus-monitor-down": "focus display below",
    "move-column-to-monitor-left": "move column to display left",
    "move-column-to-monitor-right": "move column to display right",
    "move-column-to-monitor-up": "move column to display above",
    "move-column-to-monitor-down": "move column to display below",
    "expand-column-to-available-width": "expand column to available width",
    "screenshot": "capture region",
    "screenshot-screen": "capture screen",
    "screenshot-window": "capture window",
    "quit": "quit niri",
    "power-off-monitors": "turn displays off",
    "suspend": "suspend",
    "toggle-keyboard-shortcuts-inhibit": "pass shortcuts to the window",
    "show-hotkey-overlay": "show niri key bindings",
    "next-window": "next window",
    "previous-window": "previous window",
    "set-dynamic-cast-window": "select window for casting",
    "set-dynamic-cast-monitor": "select display for casting",
    "clear-dynamic-cast-target": "clear casting target",
}

UMBRIEL_AKTIONEN = {
    "window-close": "close window",
    "window-toggle-fullscreen": "fullscreen",
    "window-toggle-maximize": "maximize/restore column",
    "window-toggle-floating": "toggle floating",
    "window-center": "center window",
    "window-cycle-width": "cycle column width",
    "window-focus-left": "focus column left",
    "window-focus-right": "focus column right",
    "window-focus-up": "focus window above",
    "window-focus-down": "focus window below",
    "window-focus-next": "next window",
    "column-move-left": "move column left",
    "column-move-right": "move column right",
    "window-move-up": "move window up",
    "window-move-down": "move window down",
    "window-consume-left": "move window into left column",
    "window-consume-or-expel-right": "merge or split column to the right",
    "workspace-next": "next workspace",
    "workspace-previous": "previous workspace",
    "window-move-to-workspace-next": "move window to next workspace",
    "window-move-to-workspace-previous": "move window to previous workspace",
    "output-focus-left": "focus display left",
    "output-focus-right": "focus display right",
    "output-focus-up": "focus display above",
    "output-focus-down": "focus display below",
    "column-move-to-output-left": "move column to display left",
    "column-move-to-output-right": "move column to display right",
    "column-move-to-output-up": "move column to display above",
    "column-move-to-output-down": "move column to display below",
    "overview-toggle": "overview",
    "cheatsheet-toggle": "show Umbriel key bindings",
    "dpms-off": "turn displays off",
    "session-quit": "log out",
}

# Womit die Zeile anfaengt, sagt die Gruppe. Die Reihenfolge ist die der
# Pruefung: die erste passende gewinnt.
GRUPPEN = [
    ("spawn", "Applications"),
    ("screenshot", "Capture"),
    ("workspace", "Workspaces"),
    ("focus-workspace", "Workspaces"),
    ("move-workspace", "Workspaces"),
    ("move-column-to-workspace", "Workspaces"),
    ("output", "Displays"),
    ("monitor", "Displays"),
    ("column", "Windows"),
    ("window", "Windows"),
    ("overview", "Windows"),
    ("quit", "Session"),
    ("suspend", "Session"),
    ("power-off", "Session"),
    ("dpms", "Session"),
]


def lies(pfad):
    try:
        with open(pfad, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def ohne_kommentare(text):
    """`//`-Kommentare weg, aber nicht innerhalb von Anfuehrungszeichen.

    Sonst verschwaende `spawn "brave" "--app=https://x"` bei den zwei
    Schraegstrichen der URL -- und mit ihr die halbe Zeile.
    """
    raus = []
    for zeile in text.splitlines():
        in_str = False
        i = 0
        while i < len(zeile):
            z = zeile[i]
            if z == '"':
                in_str = not in_str
            elif z == "/" and not in_str and zeile[i:i + 2] == "//":
                zeile = zeile[:i]
                break
            i += 1
        raus.append(zeile)
    return "\n".join(raus)


def dateien(pfad, gesehen=None):
    """Die Konfiguration, an den include-Stellen aufgeklappt."""
    gesehen = gesehen if gesehen is not None else set()
    echt = os.path.realpath(pfad)
    if echt in gesehen:
        return []
    gesehen.add(echt)

    text = ohne_kommentare(lies(pfad))
    basis = os.path.dirname(pfad)
    stuecke = []
    rest = []

    for zeile in text.splitlines():
        treffer = re.match(r'\s*include\s+"([^"]+)"', zeile)
        if not treffer:
            rest.append(zeile)
            continue
        # Das bisher Gesammelte kommt VOR der eingebundenen Datei -- die
        # Reihenfolge ist der ganze Punkt.
        if rest:
            stuecke.append((pfad, "\n".join(rest)))
            rest = []
        ziel = os.path.expanduser(treffer.group(1))
        if not os.path.isabs(ziel):
            ziel = os.path.join(basis, ziel)
        stuecke.extend(dateien(ziel, gesehen))

    if rest:
        stuecke.append((pfad, "\n".join(rest)))
    return stuecke


def binds_aus(text):
    """Die Bindungen aus einem `binds { … }`-Block, in Reihenfolge.

    Von Hand statt mit einem KDL-Parser: die Konfiguration darf nicht
    umgeschrieben werden, es wird nur gelesen, und die Form einer Bindung ist
    immer dieselbe -- Taste, Eigenschaften, geschweifte Klammer, Aktion.
    """
    ergebnis = []
    for block in re.finditer(r"\bbinds\s*\{", text):
        i = block.end()
        tiefe = 1
        while i < len(text) and tiefe > 0:
            treffer = re.match(
                r"\s*([A-Za-z0-9_+]+)((?:\s+[a-z-]+=(?:\"[^\"]*\"|[^\s{]+))*)\s*\{([^{}]*)\}",
                text[i:],
            )
            if treffer:
                ergebnis.append((treffer.group(1), treffer.group(2), treffer.group(3)))
                i += treffer.end()
                continue
            if text[i] == "{":
                tiefe += 1
            elif text[i] == "}":
                tiefe -= 1
            i += 1
    return ergebnis


def programm(aktion):
    """Aus `spawn "sh" "-c" "…"` das machen, was man wirklich startet."""
    teile = re.findall(r'"([^"]*)"', aktion)
    if not teile:
        return "startet etwas"
    # Der Umweg ueber die Shell ist Technik, keine Auskunft: was in `sh -c`
    # steht, ist der eigentliche Befehl.
    if teile[0] in ("sh", "bash", "zsh") and len(teile) >= 3:
        befehl = teile[-1]
        befehl = befehl.replace("$HOME/.local/bin/", "").replace(os.path.expanduser("~") + "/.local/bin/", "")
        return befehl
    # Webapps: die Adresse sagt mehr als der Browsername.
    for t in teile:
        if t.startswith("--app="):
            return "Webapp " + t[6:].replace("https://", "").replace("www.", "").rstrip("/")
    return " ".join([os.path.basename(teile[0])] + [t for t in teile[1:] if not t.startswith("--")])


def beschreibung(props, aktion):
    titel = re.search(r'hotkey-overlay-title="([^"]*)"', props)
    if titel and titel.group(1).strip():
        return titel.group(1).strip()

    aktion = aktion.strip().rstrip(";").strip()
    kopf = aktion.split()[0] if aktion.split() else ""

    if kopf == "spawn":
        return programm(aktion)
    # Aktionen mit einem Mass dahinter: `set-column-width "+10%"` heisst
    # breiter, `"-10%"` schmaler -- das Vorzeichen ist die halbe Auskunft und
    # geht in einer Tabelle mit lauter Prozentzeichen sonst unter.
    mass = re.match(r'^(set-column-width|set-window-height)\s+"?([+-]?\d+%?)"?$', aktion)
    if mass:
        richtung = mass.group(2).startswith("-")
        was = "column" if mass.group(1) == "set-column-width" else "window"
        return was + (" narrower " if richtung and was == "column" else " lower " if richtung else " wider " if was == "column" else " higher ") + mass.group(2).lstrip("+-")

    if kopf in AKTIONEN:
        rest = aktion[len(kopf):].strip()
        # `focus-workspace 3` -- die Zahl gehoert dazu.
        zahl = re.match(r'^"?(\d+)"?$', rest)
        if zahl:
            return AKTIONEN[kopf] + " " + zahl.group(1)
        return AKTIONEN[kopf]
    if kopf.startswith("focus-workspace"):
        rest = aktion[len(kopf):].strip().strip('"')
        return "focus workspace " + rest if rest else "switch workspace"
    if kopf.startswith("move-column-to-workspace"):
        rest = aktion[len(kopf):].strip().strip('"')
        return "move column to workspace " + rest if rest else "move column"
    return aktion or "?"


def gruppe(taste, aktion):
    # Die TASTE entscheidet mit, nicht nur die Aktion: die Lautstaerketasten
    # rufen hier ein Programm auf (`wpctl`, `dms ipc`), landeten damit unter
    # "Programme" und standen zwischen Browser und Terminal -- gesucht werden
    # sie aber beim Ton.
    if "XF86Audio" in taste or "XF86MonBrightness" in taste or "XF86Kbd" in taste:
        return "Audio and display"
    a = aktion.strip()
    if " capture " in (" " + a + " ") or "Print" in taste or "XF86Launch1" in taste:
        return "Capture"
    for stueck, name in GRUPPEN:
        if stueck in a:
            return name
    return "Other"


def taste_lesbar(taste):
    """`Mod+Shift+G` bleibt, aber die Sondernamen werden Klartext."""
    ersatz = {
        "Mod": "Mod",
        "Return": "Enter",
        "grave": "^",
        "comma": ",",
        "period": ".",
        "slash": "/",
        "minus": "-",
        "equal": "=",
        "bracketleft": "[",
        "bracketright": "]",
        "Print": "Druck",
        "WheelScrollDown": "Rad runter",
        "WheelScrollUp": "Rad hoch",
        "WheelScrollLeft": "Rad links",
        "WheelScrollRight": "Rad rechts",
        "WheelDown": "Rad runter",
        "WheelUp": "Rad hoch",
        "WheelLeft": "Rad links",
        "WheelRight": "Rad rechts",
    }
    # Gross- und Kleinschreibung sind niri egal: die eine Datei schreibt
    # `Mod+comma`, die naechste `Mod+Comma`. Ohne diesen Abgleich stuende in der
    # Liste einmal "," und einmal "Comma".
    klein = {k.lower(): v for k, v in ersatz.items()}
    return "+".join(klein.get(t.lower(), t) for t in taste.split("+"))


def umbriel_beschreibung(aktion):
    if aktion.startswith("spawn:"):
        befehl = aktion[6:].replace("$HOME/.local/bin/", "")
        if " --app=" in befehl:
            return "Webapp " + befehl.split(" --app=", 1)[1].replace("https://", "").replace("www.", "").rstrip("/")
        return befehl
    if aktion.startswith("workspace-switch:"):
        return "focus workspace " + aktion.split(":", 1)[1]
    if aktion.startswith("window-move-to-workspace:"):
        return "move window to workspace " + aktion.split(":", 1)[1]
    if aktion.startswith("window-modify-width:"):
        amount = aktion.split(":", 1)[1]
        return "column wider " + amount if not amount.startswith("-") else "column narrower " + amount[1:]
    if aktion.startswith("workspace-set-layout:"):
        return "toggle scrolling/dwindle layout"
    return UMBRIEL_AKTIONEN.get(aktion, aktion)


def umbriel_aktion(value):
    # Umbriel also accepts an inline table for binds that need metadata such as
    # allow_when_locked. The cheatsheet describes the action while preserving
    # the complete raw value separately.
    if isinstance(value, dict):
        return str(value.get("action", ""))
    return str(value)


def umbriel_main():
    with open(UMBRIEL_KONFIG, "rb") as handle:
        data = tomllib.load(handle)
    liste = []
    for taste, raw_aktion in data.get("keybinds", {}).items():
        aktion = umbriel_aktion(raw_aktion)
        liste.append({
            "taste": taste_lesbar(taste),
            "roh": taste,
            "text": umbriel_beschreibung(aktion),
            "aktion": aktion,
            "gruppe": gruppe(taste, aktion),
            "quelle": os.path.basename(UMBRIEL_KONFIG),
        })
    print(json.dumps({"ok": True, "backend": "umbriel", "binds": liste, "datei": UMBRIEL_KONFIG}, ensure_ascii=False))


def main():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    forced = os.environ.get("NBSHELL_COMPOSITOR", "").lower()
    if forced == "umbriel" or (not forced and (os.environ.get("UMBRIEL_SOCKET") or "umbriel" in desktop)):
        umbriel_main()
        return
    eintraege = {}
    reihenfolge = []

    for pfad, text in dateien(KONFIG):
        for taste, props, aktion in binds_aus(text):
            sauber = " ".join(aktion.split()).rstrip(";").strip()
            if taste not in eintraege:
                reihenfolge.append(taste)
            # Spaeter gelesen gewinnt -- wie in niri.
            eintraege[taste] = {
                "taste": taste_lesbar(taste),
                "roh": taste,
                "text": beschreibung(props, sauber),
                "aktion": sauber,
                "gruppe": gruppe(taste, sauber),
                "quelle": os.path.basename(pfad),
            }

    liste = [eintraege[t] for t in reihenfolge]
    print(json.dumps({"ok": True, "binds": liste, "datei": KONFIG}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 -- die Shell soll den Grund sehen
        print(json.dumps({"ok": False, "grund": str(e)}, ensure_ascii=False))
        sys.exit(1)
