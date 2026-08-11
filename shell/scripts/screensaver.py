#!/usr/bin/env python3
"""Bildschirmschoner: der nbshell-Schriftzug, im Terminal animiert.

Nach Omarchys Vorbild -- dort laeuft ein Vollbildterminal mit `ttfx` und einem
zufaelligen Effekt auf einer ASCII-Datei, und jeder Tastendruck beendet es.
Dasselbe hier, nur ohne das Programm: `ttfx` ist nicht in den Repos, und ein
Zeichenraster ueber neun Zeilen zu bewegen braucht keine Bibliothek.

Vier Effekte, einer nach dem anderen, in zufaelliger Reihenfolge:

    entschluesseln  die Zeichen zappeln und rasten nacheinander ein
    regen           sie fallen von oben an ihren Platz
    fegen           ein heller Balken faehrt durch und laesst sie stehen
    schreibmaschine Zeile fuer Zeile, mit blinkendem Cursor

Die Farben kommen aus dem laufenden Theme: nbshell schreibt seine Palette nach
~/.config/nbshell/palette.sh, und die wird hier gelesen. Der Schriftzug hat
damit denselben Akzent wie die Leiste, auch nach einem Themewechsel.

Beendet wird bei JEDEM Tastendruck, bei Mausbewegung im Terminal und auf
SIGTERM -- das Letzte ist der Weg, den nbshell nimmt, wenn der Leerlauf endet:
eine bewegte Maus erzeugt keinen Tastendruck, und der Bildschirmschoner soll
trotzdem verschwinden.
"""

import os
import random
import re
import shutil
import signal
import sys
import termios
import time
import tty

# Aus der eigenen Schrift gerastert (Inconsolata, 2:1 fuer die Zellenform).
WORT = r"""
             ██                         ██                          █████        █████
             ██                         ██                             ██           ██
      █      ██    █           ██       ██    █           ██           ██           ██
█████████    ██████████     ████████    █████████      ████████        ██           ██
███     ██   ███     ███   ███          ███     ██    ██     ███       ██           ██
██      ██   ██       ██     ██████     ██      ██   ███████████       ██           ██
██      ██   ██       ██          ███   ██      ██   ██                ██           ██
██      ██   ███     ██    ██      ██   ██      ██    ███     █        ██           ███
██      ██   ██ ██████      ███████      █      ██      ███████    ██████████    █████████
""".strip("\n").split("\n")

ZAPPEL = "▚▞▛▜▙▟▄▀▌▐░▒▓#*+=-_"

STANDARD_AKZENT = "#7aa2f7"
STANDARD_FG = "#a9b1d6"


def palette():
    """Akzent und Vordergrund aus dem laufenden Theme.

    Gelesen wird die Datei, die nbshell bei jedem Themewechsel schreibt. Fehlt
    sie -- weil der Export aus ist --, bleiben die Vorgaben stehen; ein
    Bildschirmschoner, der wegen einer fehlenden Datei gar nicht erst startet,
    waere die schlechtere Wahl.
    """
    pfad = os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
        "nbshell", "palette.sh")
    werte = {}
    try:
        with open(pfad) as f:
            for zeile in f:
                m = re.match(r"^(NB_[A-Z_0-9]+)='([^']*)'", zeile.strip())
                if m:
                    werte[m.group(1)] = m.group(2)
    except OSError:
        pass
    return werte.get("NB_ACCENT", STANDARD_AKZENT), werte.get("NB_FG", STANDARD_FG)


def rgb(hexwert):
    h = hexwert.lstrip("#")
    if len(h) != 6:
        h = STANDARD_AKZENT.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def farbe(c, hell=1.0):
    r, g, b = c
    r, g, b = (min(255, int(x * hell)) for x in (r, g, b))
    return f"\033[38;2;{r};{g};{b}m"


AUS = "\033[0m"


class Schirm:
    def __init__(self):
        self.w, self.h = shutil.get_terminal_size((80, 24))
        # Die Kunst sitzt mittig. Passt sie nicht, wird sie beschnitten statt
        # umgebrochen -- ein umgebrochener Schriftzug ist keiner mehr.
        self.kunst = [z[:self.w] for z in WORT]
        self.kh = len(self.kunst)
        self.kw = max(len(z) for z in self.kunst)
        self.x0 = max(0, (self.w - self.kw) // 2)
        self.y0 = max(0, (self.h - self.kh) // 2)

    def setz(self, x, y, text):
        sys.stdout.write(f"\033[{y + 1};{x + 1}H{text}")

    def leer(self):
        sys.stdout.write("\033[2J")


def zellen(s):
    for y, zeile in enumerate(s.kunst):
        for x, ch in enumerate(zeile):
            if ch != " ":
                yield x, y, ch


def effekt_entschluesseln(s, akzent, fg, halt):
    """Alles zappelt, dann rastet Zelle fuer Zelle ein."""
    offen = list(zellen(s))
    random.shuffle(offen)
    fest = {}
    while offen and not halt():
        for _ in range(max(1, len(offen) // 18)):
            if not offen:
                break
            x, y, ch = offen.pop()
            fest[(x, y)] = ch
        for x, y, ch in offen:
            s.setz(s.x0 + x, s.y0 + y, farbe(akzent, 0.5) + random.choice(ZAPPEL) + AUS)
        for (x, y), ch in fest.items():
            s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + ch + AUS)
        sys.stdout.flush()
        time.sleep(0.045)


def effekt_regen(s, akzent, fg, halt):
    """Die Zeichen fallen von oben an ihren Platz."""
    ziele = list(zellen(s))
    random.shuffle(ziele)
    unterwegs = [[x, -random.randint(1, s.y0 + s.kh), y, ch] for x, y, ch in ziele]
    while unterwegs and not halt():
        for stueck in list(unterwegs):
            x, jetzt, ziel, ch = stueck
            if jetzt >= 0:
                s.setz(s.x0 + x, jetzt, " ")
            stueck[1] += 1
            if stueck[1] >= s.y0 + ziel:
                s.setz(s.x0 + x, s.y0 + ziel, farbe(akzent) + ch + AUS)
                unterwegs.remove(stueck)
            elif stueck[1] >= 0:
                s.setz(s.x0 + x, stueck[1], farbe(fg, 0.5) + ch + AUS)
        sys.stdout.flush()
        time.sleep(0.02)


def effekt_fegen(s, akzent, fg, halt):
    """Ein heller Balken faehrt durch und laesst den Schriftzug stehen."""
    for spalte in range(s.kw + 12):
        if halt():
            return
        for x, y, ch in zellen(s):
            if x > spalte:
                continue
            d = spalte - x
            hell = 1.6 if d < 2 else (1.0 if d < 6 else 0.85)
            s.setz(s.x0 + x, s.y0 + y, farbe(akzent, hell) + ch + AUS)
        sys.stdout.flush()
        time.sleep(0.012)


def effekt_schreibmaschine(s, akzent, fg, halt):
    """Zeile fuer Zeile, mit Cursorblock am Ende."""
    for y, zeile in enumerate(s.kunst):
        for x in range(len(zeile)):
            if halt():
                return
            if zeile[x] != " ":
                s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + zeile[x] + AUS)
            if x % 3 == 0:
                s.setz(s.x0 + x + 1, s.y0 + y, farbe(fg, 1.4) + "▌" + AUS)
                sys.stdout.flush()
                time.sleep(0.004)
                s.setz(s.x0 + x + 1, s.y0 + y, " ")
        sys.stdout.flush()


def ruhe(s, akzent, fg, halt, sekunden):
    """Steht und atmet: ein langsamer Helligkeitsverlauf ueber dem Wort.

    Ein voellig unbewegtes Bild waere auf einem OLED nicht besser als ein
    Fenster -- die Wanderung sorgt dafuer, dass kein Pixel dauerhaft gleich
    hell bleibt.
    """
    ende = time.time() + sekunden
    t = 0.0
    while time.time() < ende and not halt():
        for x, y, ch in zellen(s):
            welle = 0.75 + 0.45 * (0.5 + 0.5 * __import__("math").sin((x / 9.0) - t))
            s.setz(s.x0 + x, s.y0 + y, farbe(akzent, welle) + ch + AUS)
        sys.stdout.flush()
        t += 0.28
        time.sleep(0.07)


def main():
    beendet = {"ja": False}

    def stop(*_):
        beendet["ja"] = True

    # SIGTERM ist der Weg, den nbshell nimmt: eine bewegte Maus erzeugt keinen
    # Tastendruck, der Schoner soll aber trotzdem verschwinden.
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGHUP, stop)

    akzent, fg = (rgb(x) for x in palette())
    s = Schirm()

    alt = None
    if sys.stdin.isatty():
        alt = termios.tcgetattr(sys.stdin)
        tty.setcbreak(sys.stdin.fileno())
        os.set_blocking(sys.stdin.fileno(), False)

    def halt():
        if beendet["ja"]:
            return True
        try:
            if sys.stdin.read(1):
                return True
        except (TypeError, OSError):
            pass
        return False

    # Der Fenstertitel ist die Kennung, an der niri das Fenster erkennt und
    # bildschirmfuellend oeffnet. Ueber die App-Kennung ginge es nicht:
    # ghostty vergibt sie fest (`com.mitchellh.ghostty`), `--class` aendert
    # daran nichts -- geprueft mit 1.3.1.
    sys.stdout.write("\033]0;nbshell-screensaver\007")

    # Alternativer Schirm, Cursor weg, Maus meldet Bewegung: so beendet auch
    # ein Ruckeln an der Maus, ohne dass jemand eine Taste treffen muss.
    sys.stdout.write("\033[?1049h\033[?25l\033[?1003h")
    sys.stdout.flush()
    try:
        effekte = [effekt_entschluesseln, effekt_regen, effekt_fegen, effekt_schreibmaschine]
        random.shuffle(effekte)
        i = 0
        while not halt():
            s.leer()
            effekte[i % len(effekte)](s, akzent, fg, halt)
            if halt():
                break
            ruhe(s, akzent, fg, halt, 12)
            i += 1
    finally:
        sys.stdout.write("\033[?1003l\033[?25h\033[?1049l" + AUS)
        sys.stdout.flush()
        if alt is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, alt)


if __name__ == "__main__":
    main()
