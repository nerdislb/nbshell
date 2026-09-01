#!/usr/bin/env python3
"""Bildschirmschoner: der nbshell-Schriftzug, im Terminal animiert.

Nach Omarchys Vorbild -- dort laeuft ein Vollbildterminal mit `ttfx` und einem
zufaelligen Effekt auf einer ASCII-Datei, und jeder Tastendruck beendet es.
Dasselbe hier, nur ohne das Programm: `ttfx` ist nicht in den Repos, und ein
Zeichenraster ueber neun Zeilen zu bewegen braucht keine Bibliothek.

Zehn Effekte, einer nach dem anderen, in zufaelliger Reihenfolge:

    entschluesseln  die Zeichen zappeln und rasten nacheinander ein
    regen           sie fallen von oben an ihren Platz
    fegen           ein heller Balken faehrt durch und laesst sie stehen
    schreibmaschine Zeile fuer Zeile, mit blinkendem Cursor
    matrix          Zeichenregen ueber den ganzen Schirm; wo er das Wort
                    streift, bleibt es stehen
    feuerwerk       Raketen steigen auf, zerplatzen, die Funken sinken auf
                    ihre Plaetze
    schwarzesloch   alles wird in die Mitte gesogen und wieder ausgeworfen
    strahlen        Lichtbalken fahren waagerecht und senkrecht durch
    brennen         das Wort brennt von unten nach oben an
    schnitt         waagerecht durchgeschnitten, beide Haelften fahren ein

Vorbild ist TTE (terminaltexteffects), das Omarchy benutzt -- das bringt 39
Effekte mit. So viele werden es hier nicht.

Omarchy ruft TTE so auf:

    ttfx -i screensaver.txt --frame-rate 120 --canvas-width 0 --canvas-height 0
         --reuse-canvas --anchor-canvas c --anchor-text c --random-effect

Drei davon sind uebernommen, und sie machen den Unterschied:

  --frame-rate 120      hier: ein Bild alle 8-12 ms statt alle 30-45. Was
                        vorher ruckelte, fliesst.
  --canvas 0            die Leinwand ist der GANZE Schirm, nicht der Kasten um
                        den Text. Effekte duerfen von weit ausserhalb kommen --
                        das ist der halbe Eindruck.
  --reuse-canvas        zwischen zwei Effekten wird nicht geloescht; der
                        Uebergang blitzt sonst schwarz auf.

Die Farben kommen aus dem laufenden Theme: nbshell schreibt seine Palette nach
~/.config/nbshell/palette.sh, und die wird hier gelesen. Der Schriftzug hat
damit denselben Akzent wie die Leiste, auch nach einem Themewechsel.

Beendet wird bei jedem Tastendruck und auf SIGTERM. Das SIGTERM ist der Weg,
den nbshell nimmt, sobald der Leerlauf endet -- und damit auch der Weg, auf dem
eine bewegte Maus ihn beendet: die meldet sich beim Kompositor, nicht hier.

Die Maus-Meldung des Terminals (`?1003h`) war der erste Versuch und ein
Eigentor: schon das Hineinfahren des Zeigers in das neu geoeffnete
Vollbildfenster schickt ein Ereignis, und der Schoner ging in derselben
Sekunde wieder zu, in der er aufging. Dieselbe Falle stellt der Start selbst --
der Tastendruck oder Klick, mit dem man ihn ausloest, liegt danach noch im
Puffer. Deshalb: Puffer leeren und eine kurze Schonfrist, bevor ueberhaupt
hingehoert wird.
"""

import math
import os
import random
import re
import select
import shutil
import signal
import sys
import termios
import time
import tty

# Aus der eigenen Schrift gerastert, mit HALBBLOECKEN (▀▄█).
#
# Der erste Wurf nahm nur den vollen Block und sah daneben grob aus. Omarchys
# Logo (81x10) benutzt genau diese drei Zeichen -- damit hat eine Textzeile
# zwei Pixelzeilen, und die Rundungen von b, s, e kommen ueberhaupt erst zur
# Geltung. Das ist der eigentliche Unterschied gewesen, nicht die Groesse.
#
# Zwei Fassungen: im Vollbild misst das Terminal hier 239 Spalten, da passt die
# grosse bequem. Die kleine ist fuer alles andere -- ein abgeschnittener
# Schriftzug ist keiner.
GROSS = r"""
                             ████                                                       █████                                                       ████████████                 ████████████
                             ████                                                       █████                                                              █████                         ████
                             ████                                                       █████                                                              █████                         ████
████  ▄▄██████████▄▄         ████ ▄▄▄██████████▄▄            ▄▄█████████████▄▄▄         █████ ▄▄▄█████████▄▄            ▄▄▄███████████▄▄▄                  █████                         ████
██████▀▀       ▀▀████        ██████▀▀        ▀████▄         ████            ▀█▀         ██████▀▀        ▀████         ▄███▀          ▀████▄                █████                         ████
████▀            ████        ████▀             ▀████        ▀▀████▄▄▄▄                  █████            ████▄      ▄████ ▄          ▄ ████▄               █████                         ████
████             ████        ████               ████             ▀▀▀▀▀██████▄▄▄         █████            █████      █████▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀               █████                         ████
████             ████        ████▄             ▄████                      ▀▀████▄       █████            █████      ▀████                                  █████                         ████
████             ████        ██████▄▄       ▄▄████▀       ▄▄██▄▄           ▄████        █████            █████        ▀████▄▄         ▄▄▄▄                 █████                         ████
████             ████        ███▀ ▀▀▀████████▀▀▀            ▀▀▀▀███████████▀▀▀          ▀███▀            ▀███▀           ▀▀▀███████████▀▀▀         ▀███████████████████▀         ████████████████████
""".strip("\n").split("\n")

KLEIN = r"""
              ███                           ██                            ▀▀▀██         ▀▀▀▀██
▄▄ ▄▄▄▄▄▄     ███▄▄▄▄▄▄▄       ▄▄▄▄▄▄▄▄     ██ ▄▄▄▄▄▄       ▄▄▄▄▄▄▄▄         ██             ██
██▀▀    ▀█▄   ███▀     ▀█▄    ██▄▄    ▀     ██▀     ██    ▄█▀      ██        ██             ██
██       ██   ███       ██       ▀▀▀▀██▄    ██      ██▀   ██▀▀▀▀▀▀▀▀▀        ██             ██
██      ▀██   ██▀█▄▄▄▄██▀    ▀██▄▄▄▄▄▄█▀    ██      ██▀    ▀██▄▄▄▄▄█     ▄▄▄▄███▄▄▄     ▄▄▄▄██▄▄▄▄
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


def zeig():
    """Ausgabe rausschreiben, ohne daran zu scheitern.

    Ein Terminal, das gerade nicht annimmt, ist ein Grund zu warten -- kein
    Grund, den Bildschirmschoner zu beenden. (Der urspruengliche Absturz kam
    von woanders, siehe `main`; das hier ist das Netz darunter.)
    """
    try:
        sys.stdout.flush()
    except BlockingIOError:
        time.sleep(0.008)


class Schirm:
    def __init__(self):
        self.w, self.h = shutil.get_terminal_size((80, 24))
        # Die Kunst sitzt mittig. Passt sie nicht, wird sie beschnitten statt
        # umgebrochen -- ein umgebrochener Schriftzug ist keiner mehr.
        # Die grosse Fassung nur, wenn sie ganz hineinpasst.
        breit = max(len(z) for z in GROSS)
        passt = self.w >= breit + 4 and self.h >= len(GROSS) + 6
        self.kunst = GROSS if passt else [z[:self.w] for z in KLEIN]
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
        zeig()
        time.sleep(0.006)


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
        zeig()
        time.sleep(0.008)


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
        zeig()
        time.sleep(0.006)


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
                zeig()
                time.sleep(0.002)
                s.setz(s.x0 + x + 1, s.y0 + y, " ")
        zeig()


def effekt_matrix(s, akzent, fg, halt):
    """Zeichenregen ueber den ganzen Schirm; das Wort bleibt zurueck.

    Der Regen faellt ueber die volle Breite, nicht nur ueber das Wort -- sonst
    sieht man sofort, wo der Schriftzug steht, und die Aufloesung am Ende ist
    keine Ueberraschung mehr.
    """
    ziele = {(x, y): ch for x, y, ch in zellen(s)}
    fest = {}
    spalten = [random.randint(-s.h, 0) for _ in range(s.w)]
    tempo = [random.choice((1, 1, 2)) for _ in range(s.w)]
    runden = 0
    while runden < 90 and not halt():
        for x in range(s.w):
            kopf = spalten[x]
            # Der Schweif hinter dem Kopf verblasst.
            for i, hell in ((0, 1.6), (1, 0.9), (2, 0.6), (3, 0.35), (7, 0.0)):
                y = kopf - i
                if not (0 <= y < s.h):
                    continue
                if (x - s.x0, y - s.y0) in fest:
                    continue
                if hell == 0.0:
                    s.setz(x, y, " ")
                else:
                    s.setz(x, y, farbe(akzent, hell) + random.choice(ZAPPEL) + AUS)
            # Streift der Kopf eine Zelle des Wortes, rastet sie ein.
            zk = (x - s.x0, kopf - s.y0)
            if zk in ziele and zk not in fest and runden > 12:
                fest[zk] = ziele[zk]
            spalten[x] += tempo[x]
            if spalten[x] > s.h + 8:
                spalten[x] = random.randint(-12, -1)
        for (x, y), ch in fest.items():
            s.setz(s.x0 + x, s.y0 + y, farbe(akzent, 1.5) + ch + AUS)
        zeig()
        runden += 1
        time.sleep(0.01)
        if len(fest) == len(ziele):
            break
    for (x, y), ch in ziele.items():
        s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + ch + AUS)
    zeig()


def effekt_feuerwerk(s, akzent, fg, halt):
    """Raketen steigen, zerplatzen, die Funken sinken auf ihre Plaetze."""
    ziele = list(zellen(s))
    random.shuffle(ziele)
    gruppen = [ziele[i::5] for i in range(5)]
    gesetzt = []
    for gruppe in gruppen:
        if halt():
            break
        start_x = random.randint(s.w // 5, s.w * 4 // 5)
        gipfel = random.randint(2, max(3, s.y0))
        # Aufstieg
        for y in range(s.h - 1, gipfel, -3):
            if halt():
                return
            s.setz(start_x, y, farbe(fg, 1.4) + "│" + AUS)
            s.setz(start_x, min(s.h - 1, y + 3), " ")
            for x, yy, ch in gesetzt:
                s.setz(s.x0 + x, s.y0 + yy, farbe(akzent) + ch + AUS)
            zeig()
            time.sleep(0.006)
        s.setz(start_x, gipfel, " ")
        # Explosion: die Funken fliegen von der Rakete zu ihren Plaetzen.
        schritte = 9
        for i in range(schritte + 1):
            if halt():
                return
            anteil = i / schritte
            for x, y, ch in gruppe:
                zx, zy = s.x0 + x, s.y0 + y
                px = round(start_x + (zx - start_x) * anteil)
                py = round(gipfel + (zy - gipfel) * anteil)
                if 0 <= px < s.w and 0 <= py < s.h:
                    s.setz(px, py, farbe(akzent, 1.5 - anteil * 0.5) + (ch if anteil > 0.75 else random.choice("·∙*")) + AUS)
            zeig()
            time.sleep(0.01)
            if i < schritte:
                for x, y, ch in gruppe:
                    anteil2 = i / schritte
                    px = round(start_x + (s.x0 + x - start_x) * anteil2)
                    py = round(gipfel + (s.y0 + y - gipfel) * anteil2)
                    if 0 <= px < s.w and 0 <= py < s.h:
                        s.setz(px, py, " ")
        gesetzt.extend(gruppe)
        for x, y, ch in gruppe:
            s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + ch + AUS)
        zeig()


def effekt_schwarzesloch(s, akzent, fg, halt):
    """Alles wird in die Mitte gesogen und wieder ausgeworfen."""
    ziele = list(zellen(s))
    mx, my = s.w // 2, s.h // 2
    # Erst auf einem Ring verteilt einsammeln, dann nach aussen an den Platz.
    for phase, (von_ring, nach_ring) in enumerate(((True, False), (False, True))):
        schritte = 14
        for i in range(schritte + 1):
            if halt():
                return
            a = i / schritte
            for n, (x, y, ch) in enumerate(ziele):
                winkel = n * 0.7 + a * (6.0 if von_ring else 3.0)
                radius = (1 - a) * max(s.w, s.h) * 0.42 if von_ring else a * 0.0
                if von_ring:
                    px = round(mx + math.cos(winkel) * radius * 1.6)
                    py = round(my + math.sin(winkel) * radius * 0.7)
                else:
                    px = round(mx + (s.x0 + x - mx) * a)
                    py = round(my + (s.y0 + y - my) * a)
                if 0 <= px < s.w and 0 <= py < s.h:
                    s.setz(px, py, farbe(akzent, 0.6 + a * 0.9) + (ch if not von_ring and a > 0.8 else random.choice("·∙•")) + AUS)
            zeig()
            time.sleep(0.012)
            s.leer()
    for x, y, ch in ziele:
        s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + ch + AUS)
    zeig()


def effekt_strahlen(s, akzent, fg, halt):
    """Lichtbalken fahren waagerecht und senkrecht durch das Wort."""
    ziele = {(x, y): ch for x, y, ch in zellen(s)}
    hell = {}
    for durchgang in ("waagerecht", "senkrecht"):
        # Ueber den GANZEN Schirm, nicht nur ueber den Kasten um das Wort:
        # der Balken kommt dann sichtbar von weit her (Omarchys canvas 0).
        laenge = s.h if durchgang == "waagerecht" else s.w
        for pos in range(laenge + 6):
            if halt():
                return
            for (x, y), ch in ziele.items():
                d = abs(((s.y0 + y) if durchgang == "waagerecht" else (s.x0 + x)) - pos)
                if d == 0:
                    hell[(x, y)] = 1.9
                elif (x, y) not in hell:
                    hell[(x, y)] = 0.32
                s.setz(s.x0 + x, s.y0 + y, farbe(akzent, hell[(x, y)]) + ch + AUS)
                if hell[(x, y)] > 1.0:
                    hell[(x, y)] = max(1.0, hell[(x, y)] - 0.22)
            zeig()
            time.sleep(0.03 if durchgang == "waagerecht" else 0.012)


def effekt_brennen(s, akzent, fg, halt):
    """Das Wort brennt von unten nach oben an."""
    ziele = list(zellen(s))
    glut = ((255, 220, 120), (255, 150, 40), (220, 70, 20))
    for reihe in range(s.kh - 1, -2, -1):
        for zuck in range(4):
            if halt():
                return
            for x, y, ch in ziele:
                if y > reihe + 1:
                    s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + ch + AUS)
                elif y >= reihe:
                    c = glut[random.randint(0, 2)]
                    s.setz(s.x0 + x, s.y0 + y, farbe(c, 1.0) + random.choice("▓▒░") + AUS)
                else:
                    s.setz(s.x0 + x, s.y0 + y, " ")
            zeig()
            time.sleep(0.01)
    for x, y, ch in ziele:
        s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + ch + AUS)
    zeig()


def effekt_schnitt(s, akzent, fg, halt):
    """Waagerecht durchgeschnitten; beide Haelften fahren von aussen ein."""
    mitte = s.kh // 2
    weit = s.w
    for schritt in range(weit, -1, -max(1, weit // 26)):
        if halt():
            return
        s.leer()
        for x, y, ch in zellen(s):
            versatz = -schritt if y < mitte else schritt
            px = s.x0 + x + versatz
            if 0 <= px < s.w:
                s.setz(px, s.y0 + y, farbe(akzent, 1.0 if schritt < weit // 6 else 0.75) + ch + AUS)
        zeig()
        time.sleep(0.008)
    for x, y, ch in zellen(s):
        s.setz(s.x0 + x, s.y0 + y, farbe(akzent) + ch + AUS)
    zeig()


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
            welle = 0.75 + 0.45 * (0.5 + 0.5 * math.sin((x / 9.0) - t))
            s.setz(s.x0 + x, s.y0 + y, farbe(akzent, welle) + ch + AUS)
        zeig()
        t += 0.28
        time.sleep(0.05)


def wortmarke_ausgeben():
    """Den Schriftzug als Textdatei ausgeben -- Futter fuer TTE.

    Damit liegt die Vorlage an genau einer Stelle: hier. Wer sie aendern will,
    schreibt in ~/.config/nbshell/screensaver.txt; das Startskript nimmt die
    Datei, wenn es sie findet, und sonst diese Ausgabe.
    """
    breit = max(len(z) for z in GROSS)
    spalten = shutil.get_terminal_size((239, 63)).columns
    art = GROSS if spalten >= breit + 4 else KLEIN
    print("\n".join(art))


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("--wortmarke", "-w"):
        wortmarke_ausgeben()
        return

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

    # NICHT os.set_blocking(stdin, False): an einem Terminal teilen sich stdin,
    # stdout und stderr DIESELBE Dateibeschreibung. Wer stdin auf
    # nicht-blockierend stellt, stellt die Ausgabe gleich mit um -- und der
    # erste groessere Bildaufbau scheitert mit "BlockingIOError: write could
    # not complete without blocking". Genau daran ist der Schoner abgestuerzt,
    # Sekunden nachdem er aufging.
    #
    # Ob eine Taste anliegt, beantwortet `select`: es fragt, ohne etwas am
    # Zustand der Datei zu aendern. Gelesen wird dann mit os.read, weil ein
    # blockierendes sys.stdin.read(1) genau hier haengen bliebe.
    def taste_liegt_an():
        if alt is None:
            return False
        try:
            bereit, _, _ = select.select([sys.stdin], [], [], 0)
            if not bereit:
                return False
            return bool(os.read(sys.stdin.fileno(), 1024))
        except (OSError, ValueError):
            return False

    # Was beim Starten noch im Puffer liegt, gehoert nicht dazu.
    while taste_liegt_an():
        pass

    # Vor Ablauf der Schonfrist wird gar nicht erst hingehoert: der Klick oder
    # Tastendruck, mit dem man den Schoner startet, trifft sonst ihn selbst.
    frist = time.time() + 1.2

    def halt():
        if beendet["ja"]:
            return True
        if time.time() < frist:
            return False
        return taste_liegt_an()

    # The window title is the identifier Umbriel uses to match the fullscreen
    # bildschirmfuellend oeffnet. Ueber die App-Kennung ginge es nicht:
    # ghostty vergibt sie fest (`com.mitchellh.ghostty`), `--class` aendert
    # daran nichts -- geprueft mit 1.3.1.
    sys.stdout.write("\033]0;nbshell-screensaver\007")

    # Alternativer Schirm, Cursor weg. KEINE Maus-Meldung -- siehe Kopf.
    sys.stdout.write("\033[?1049h\033[?25l")
    zeig()
    try:
        effekte = [effekt_entschluesseln, effekt_regen, effekt_fegen,
                   effekt_schreibmaschine, effekt_matrix, effekt_feuerwerk,
                   effekt_schwarzesloch, effekt_strahlen, effekt_brennen,
                   effekt_schnitt]
        random.shuffle(effekte)
        i = 0
        s.leer()
        while not halt():
            # KEIN Loeschen zwischen zwei Effekten (Omarchys --reuse-canvas):
            # der Uebergang blitzt sonst schwarz auf.
            effekte[i % len(effekte)](s, akzent, fg, halt)
            if halt():
                break
            ruhe(s, akzent, fg, halt, 4)
            i += 1
    finally:
        sys.stdout.write("\033[?25h\033[?1049l" + AUS)
        zeig()
        if alt is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, alt)


if __name__ == "__main__":
    main()
