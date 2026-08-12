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

KONFIG = os.path.expanduser(
    os.environ.get("NBSHELL_NIRI_CONFIG", "~/.config/niri/config.kdl")
)

# Was die Aktionen bedeuten. Nur die, die niri wirklich hat -- ein Eintrag, den
# niemand benutzt, kostet nichts, ein falscher kostet Vertrauen.
AKTIONEN = {
    "close-window": "Fenster schliessen",
    "fullscreen-window": "Vollbild",
    "toggle-windowed-fullscreen": "Vollbild im Fenster",
    "maximize-column": "Spalte gross/klein",
    "center-column": "Spalte mittig",
    "center-visible-columns": "sichtbare Spalten mittig",
    "consume-or-expel-window-left": "Fenster in die Spalte links",
    "consume-or-expel-window-right": "Fenster in die Spalte rechts",
    "consume-window-into-column": "Fenster in die Spalte holen",
    "expel-window-from-column": "Fenster aus der Spalte loesen",
    "switch-preset-column-width": "Spaltenbreite durchschalten",
    "switch-preset-window-height": "Fensterhoehe durchschalten",
    "reset-window-height": "Fensterhoehe zuruecksetzen",
    "toggle-window-floating": "schwebend/verankert",
    "switch-focus-between-floating-and-tiling": "zwischen schwebend und verankert",
    "toggle-column-tabbed-display": "Spalte als Reiter",
    "toggle-overview": "Uebersicht",
    "focus-column-left": "eine Spalte nach links",
    "focus-column-right": "eine Spalte nach rechts",
    "focus-column-first": "zur ersten Spalte",
    "focus-column-last": "zur letzten Spalte",
    "focus-window-up": "ein Fenster nach oben",
    "focus-window-down": "ein Fenster nach unten",
    "focus-window-or-workspace-up": "Fenster oder Flaeche nach oben",
    "focus-window-or-workspace-down": "Fenster oder Flaeche nach unten",
    "move-column-left": "Spalte nach links schieben",
    "move-column-right": "Spalte nach rechts schieben",
    "move-column-to-first": "Spalte ganz nach vorn",
    "move-column-to-last": "Spalte ganz nach hinten",
    "move-window-up": "Fenster nach oben schieben",
    "move-window-down": "Fenster nach unten schieben",
    "move-window-up-or-to-workspace-up": "Fenster nach oben oder eine Flaeche hoch",
    "move-window-down-or-to-workspace-down": "Fenster nach unten oder eine Flaeche runter",
    "focus-workspace-up": "eine Arbeitsflaeche hoch",
    "focus-workspace-down": "eine Arbeitsflaeche runter",
    "focus-workspace-previous": "zurueck zur letzten Flaeche",
    "move-column-to-workspace-up": "Spalte eine Flaeche hoch",
    "move-column-to-workspace-down": "Spalte eine Flaeche runter",
    "move-workspace-up": "Arbeitsflaeche hoch",
    "move-workspace-down": "Arbeitsflaeche runter",
    "focus-monitor-left": "Bildschirm links",
    "focus-monitor-right": "Bildschirm rechts",
    "focus-monitor-up": "Bildschirm oben",
    "focus-monitor-down": "Bildschirm unten",
    "move-column-to-monitor-left": "Spalte auf den Bildschirm links",
    "move-column-to-monitor-right": "Spalte auf den Bildschirm rechts",
    "move-column-to-monitor-up": "Spalte auf den Bildschirm oben",
    "move-column-to-monitor-down": "Spalte auf den Bildschirm unten",
    "expand-column-to-available-width": "Spalte auf die freie Breite ziehen",
    "screenshot": "Ausschnitt aufnehmen",
    "screenshot-screen": "Bildschirm aufnehmen",
    "screenshot-window": "Fenster aufnehmen",
    "quit": "niri beenden",
    "power-off-monitors": "Bildschirme aus",
    "suspend": "Bereitschaft",
    "toggle-keyboard-shortcuts-inhibit": "Tastenkuerzel an das Fenster abgeben",
    "show-hotkey-overlay": "niris eigene Tastenuebersicht",
    "next-window": "naechstes Fenster",
    "previous-window": "vorheriges Fenster",
    "set-dynamic-cast-window": "Fenster fuer die Uebertragung",
    "set-dynamic-cast-monitor": "Bildschirm fuer die Uebertragung",
    "clear-dynamic-cast-target": "Uebertragung loesen",
}

# Womit die Zeile anfaengt, sagt die Gruppe. Die Reihenfolge ist die der
# Pruefung: die erste passende gewinnt.
GRUPPEN = [
    ("spawn", "Programme"),
    ("screenshot", "Aufnahme"),
    ("workspace", "Arbeitsflaechen"),
    ("focus-workspace", "Arbeitsflaechen"),
    ("move-workspace", "Arbeitsflaechen"),
    ("move-column-to-workspace", "Arbeitsflaechen"),
    ("monitor", "Bildschirme"),
    ("column", "Fenster"),
    ("window", "Fenster"),
    ("overview", "Fenster"),
    ("quit", "Sitzung"),
    ("suspend", "Sitzung"),
    ("power-off", "Sitzung"),
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
        was = "Spalte" if mass.group(1) == "set-column-width" else "Fenster"
        return was + (" schmaler " if richtung and was == "Spalte" else " niedriger " if richtung else " breiter " if was == "Spalte" else " hoeher ") + mass.group(2).lstrip("+-")

    if kopf in AKTIONEN:
        rest = aktion[len(kopf):].strip()
        # `focus-workspace 3` -- die Zahl gehoert dazu.
        zahl = re.match(r'^"?(\d+)"?$', rest)
        if zahl:
            return AKTIONEN[kopf] + " " + zahl.group(1)
        return AKTIONEN[kopf]
    if kopf.startswith("focus-workspace"):
        rest = aktion[len(kopf):].strip().strip('"')
        return "zur Arbeitsflaeche " + rest if rest else "Arbeitsflaeche wechseln"
    if kopf.startswith("move-column-to-workspace"):
        rest = aktion[len(kopf):].strip().strip('"')
        return "Spalte auf Arbeitsflaeche " + rest if rest else "Spalte verschieben"
    return aktion or "?"


def gruppe(taste, aktion):
    # Die TASTE entscheidet mit, nicht nur die Aktion: die Lautstaerketasten
    # rufen hier ein Programm auf (`wpctl`, `dms ipc`), landeten damit unter
    # "Programme" und standen zwischen Browser und Terminal -- gesucht werden
    # sie aber beim Ton.
    if "XF86Audio" in taste or "XF86MonBrightness" in taste or "XF86Kbd" in taste:
        return "Ton und Licht"
    a = aktion.strip()
    for stueck, name in GRUPPEN:
        if stueck in a:
            return name
    return "Sonstiges"


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
    }
    # Gross- und Kleinschreibung sind niri egal: die eine Datei schreibt
    # `Mod+comma`, die naechste `Mod+Comma`. Ohne diesen Abgleich stuende in der
    # Liste einmal "," und einmal "Comma".
    klein = {k.lower(): v for k, v in ersatz.items()}
    return "+".join(klein.get(t.lower(), t) for t in taste.split("+"))


def main():
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
