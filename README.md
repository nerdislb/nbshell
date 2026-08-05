# nbshell

Eine eigene Shell fuer Wayland, gebaut auf [Quickshell](https://quickshell.org)
und niri.

Kern ist eine **Insel**, die bei Bedarf offen stehen bleibt oder zum
**durchgehenden Balken** aufmacht.
Das Aussehen orientiert sich an [Omarchy](https://omarchy.org) und an einer
Terminaloberflaeche: Monospace, gerade Kanten, 1 px Rahmen, Farben aus derselben
Palette wie das Terminal. Kein Material Design.

Stand: **1.10.0** — alles, was vorher als DMS-Plugin lief, ist jetzt hier. Es laeuft: Insel, Pille und Balken, Popouts, Themewahl mit
Farbproben, Hintergrundbild am Theme, Audio, Control Center, Anwendungsstarter, Einblendung, System-Tray, Benachrichtigungen, Power-Menue, Zwischenablage, Medien, Prozessliste, Aufnahme, Terminalfarben, KI-Verbrauch, Optionsmenue, Arbeitsflaechen, Fenstertitel, Uhr, Systemlast, Tastaturbelegung,
Akku, Kalender. Alles Weitere steht unter „Was noch fehlt".

## Auf einem neuen Rechner

Der ganze Weg, in fuenf Schritten. Wer es eilig hat: Schritt 2 und 4 genuegen.

Das Ziel ist, dass beide Rechner dasselbe Setup haben -- nicht nur dieselbe
Leiste. Deshalb holt `setup.sh` auch das Dotfiles-Repo mit.

**1. Voraussetzungen.** Arch (oder ein Derivat mit `pacman`) und **niri** als
Kompositor. Ein anderer Wayland-Kompositor geht nicht: die Arbeitsflaechen, der
Fenstertitel und die Screenshots reden ueber `niri msg` mit ihm. Das Repo ist
privat, der Zugang laeuft also ueber SSH:

```bash
ssh -T git@github.com     # muss deinen Namen nennen, nicht nach Passwort fragen
```

**2. Holen und einrichten.** Ein Befehl fuer alles:

```bash
git clone git@github.com:nerdislb/nbshell.git ~/projects/nbshell
cd ~/projects/nbshell && ./setup.sh
```

`setup.sh` macht der Reihe nach:

1. **Pakete** -- die 31, die nbshell braucht
2. **Dienste** -- NetworkManager, bluetooth, tuned (fragt, siehe unten)
3. **Dotfiles** -- holt `dotfiles-dms`, zieht dessen Paketlisten nach
   (110 Repo- und 10 AUR-Pakete) und spielt mit `restore.sh` niri, ghostty,
   nvim, zsh, DMS und den Kalender ein
4. **Dateien** -- Shell, Themes, Plugins, Unit, Tastenkuerzel, der Befehl
5. **Gegenprobe** -- stehen die Befehle wirklich im `PATH`?

nbshell allein macht zwei Rechner naemlich noch nicht gleich; der Rest liegt im
Dotfiles-Repo. Zwei Dinge dabei sind wichtig genug, um sie zu kennen:

- **`restore.sh` ersetzt `~/.local/bin` vollstaendig.** Was dort liegt und
  nicht im Dotfiles-Repo steht, ist danach weg -- das `agy`-Binary etwa, das
  wegen seiner Groesse bewusst nicht im Repo liegt. Von allem Ueberschriebenen
  legt es vorher eine `.bak`-Kopie an, und es fragt selbst noch einmal nach.
- **Hardware-Pakete bleiben aussen vor.** `pkglist.txt` ist ein `pacman -Qqe`
  und enthaelt damit Kernel, Firmware und Grafiktreiber -- 20 von 130.
  `nvidia-open` auf einem AMD-Rechner ist kein Fehler, der auffaellt: es liegt
  einfach da und wird bei jedem Update mitgebaut. Sie werden aufgelistet und
  nur mit `--with-hardware` mitgenommen.

Steht `~/.local/bin` nicht im `PATH`, sagt das Skript das -- sonst findet die
Shell den Befehl `nbshell` nicht.

**3. Ausprobieren.**

```bash
nbshell start -d
```

Die Leiste sollte oben stehen. Tut sie es nicht, `nbshell start` ohne `-d`
starten: dann stehen die Meldungen im Terminal.

**4. Dauerhaft einrichten.**

```bash
nbshell switch on
```

Das bindet die Tastenkuerzel in die niri-Config ein, schaltet den
Benachrichtigungsserver und das Hintergrundbild an, faerbt ghostty mit und legt
den Autostart an. Laeuft DankMaterialShell auf dem Rechner, weicht sie dabei
zur Seite (`nbshell switch off` holt sie zurueck); ohne DMS sind diese Schritte
einfach wirkungslos. `nbshell switch status` zeigt, was gerade gilt.

**5. Was kein Skript mitbringen kann.** Drei Dinge musst du von Hand nachholen,
und zwar aus gutem Grund:

| | |
|---|---|
| **selbst installierte Themes** | Im Repo liegen 21 Stueck. Alles, was du dir mit `nbshell theme install` dazugeholt hast, fehlt drueben -- die `config.json` zeigt dann auf ein Theme, das es nicht gibt, und nbshell faellt auf seine Vorgabefarben zurueck. `nbshell theme list` zeigt hier, welche „selbst installiert" sind. |
| **Kalenderkonten** | Die iCal-Adressen in `~/.config/vdirsyncer/config` sind so gut wie Passwoerter und liegen deshalb in **keinem** Repo. Im Dotfiles-Repo steht nur `config.template` mit Platzhaltern -- die Adressen traegst du selbst ein. |
| **der Ort fuers Wetter** | `nbshell set weatherPlace Graz` |

Danach ist der zweite Rechner derselbe wie dieser.

## Installieren

Es gibt **zwei** Skripte, und der Unterschied ist genau einer: wer die Pakete
holt.

| | |
|---|---|
| `setup.sh` | Pakete, Dotfiles, Dateien, Dienste -- der ganze Rechner |
| `install.sh` | nur die Dateien von nbshell; sagt, was fehlt, holt aber **nichts** |

`install.sh` ist der richtige Weg, wenn man nicht weiss, wem der Rechner
gehoert -- Pakete sind eine Entscheidung. `setup.sh` ist der andere Fall: es
holt alles, damit hinterher kein Baustein still bleibt und kein Knopf ins Leere
greift. Es ruft `install.sh` am Ende selbst auf.

```bash
./setup.sh --no-packages    # nur die Dateien (dasselbe wie install.sh)
./setup.sh --no-dotfiles    # ohne das Dotfiles-Repo, nur nbshell
./setup.sh --no-aur         # den AUR-Helfer nicht bauen
./setup.sh --with-hardware  # auch nvidia, ucode, mesa … aus der Paketliste
./setup.sh --yes            # nichts fragen
```

**Alles ausser dem AUR-Helfer liegt in den offiziellen Repos** -- auch
`quickshell`. Es ist also ein `pacman -S --needed` und sonst nichts.

Die Reihenfolge in `setup.sh` ist keine Geschmacksfrage: **Dotfiles vor
Dateien.** `restore.sh` ersetzt `~/.local/bin` als Ganzes, also auch den Befehl
`nbshell` darin -- andersherum gewaenne die Kopie aus dem Dotfiles-Repo, und
die ist nur so neu wie das letzte `save.sh`.

Vier Dinge macht `setup.sh` bewusst **nicht** von allein:

- **Dienste einschalten.** Es fragt. Wer sein Netz mit systemd-networkd oder
  iwd verwaltet, staende nach einem beherzten `enable NetworkManager` ohne
  Verbindung da -- ein teurer Preis fuer eine Zahl in der Leiste. Bei
  NetworkManager ist die Vorgabe deshalb „nein".
- **Den AUR-Helfer bauen.** Das ist der einzige Schritt, der Code von
  ausserhalb der Repos uebersetzt und ausfuehrt. Danach wird immer gefragt,
  auch mit `--yes`.
- **Als root laufen.** Es weist das ab: die Dateien gehoeren in `$HOME`, ein
  `sudo ./setup.sh` legte sie in `/root` ab. Fuer pacman ruft es sudo selbst
  auf, an einer einzigen Stelle.
- **Hardware-Pakete aus der Paketliste holen.** Nur mit `--with-hardware`, und
  auch mit `--yes` nicht. Sie stehen vorher als Liste da.

Zum Schluss macht es die Gegenprobe: nicht ob die Pakete installiert sind,
sondern ob die Befehle wirklich im PATH stehen. Das ist nicht dasselbe.

| gebraucht | wofuer |
|---|---|
| `quickshell`, `niri` | ohne die beiden laeuft gar nichts |
| `ttf-inconsolata-nerd` | die voreingestellte Schrift (`font` in der Config) |

| optional | was sonst still bleibt |
|---|---|
| `networkmanager`, `bluez`, `bluez-utils` | Netz und Bluetooth im Control Center |
| `pipewire`, `wireplumber`, `libpulse` | Lautstaerke; `pactl` fuer den Ton der Aufnahme |
| `upower` | Akku |
| `wl-clipboard` | Zwischenablage |
| `hyprlock` | Sperren (`lockCommand`) |
| `pacman-contrib` | `checkupdates` -- der schnelle Weg des Updaters |
| `fakeroot` | sein Rueckweg, wenn `checkupdates` fehlt |
| `paru` oder `yay` | AUR-Updates und das Aktualisieren selbst |
| `tuned` | Energieprofile im Akku-Popout |
| `libnotify` | Meldungen der Skripte (Screenshot, OCR) |
| `xdg-utils` | `xdg-open` nach einer Aufnahme |
| `jq` | die Skripte |
| `git` | Themes nachinstallieren |
| `khal`, `vdirsyncer` | Kalender hinter der Uhr |
| `curl` | Wetter-Plugin |
| `wf-recorder`, `slurp` | Bildschirmaufnahme, Bereichswahl |
| `satty`, `swappy` | Screenshots nachbearbeiten |
| `tesseract` + Sprachdaten | Texterkennung |

**Zwei Dinge kommen NICHT mit** und bleiben auf einem frischen Rechner leer:

- **Wallpaper.** Die 21 Themes enthalten nur ihre `colors.toml` (84 KB statt
  91 MB). Die Bilder holt `omarchy2dms --fetch-wallpapers` einmalig in einen
  Zwischenspeicher, den nbshell mitbenutzt -- oder ein per
  `nbshell theme install` geholtes Theme bringt sein `backgrounds/` selbst mit.
- **Der KI-Verbrauch.** Der Baustein `ai` braucht `get-provider-usage` aus dem
  DMS-Plugin `aiOverviewControl`. Fehlt es, bleibt die Zelle still (`aiHelper`
  in der Config zeigt auf einen eigenen Pfad).

Gebraucht werden `quickshell` und `niri`; als Schrift ist
`Inconsolata Nerd Font Mono` voreingestellt (Paket `ttf-inconsolata-nerd`).
Das Skript legt drei Dinge an:

| | |
|---|---|
| `~/.config/quickshell/nbshell/` | die Shell selbst (`qs -c nbshell` sucht hier) |
| `~/.config/nbshell/` | `config.json` und die Themes — das, was dir gehoert |
| `~/.local/bin/nbshell` | der Befehl |

Die `config.json` wird nur angelegt, wenn es sie noch nicht gibt.

## Bedienen

```bash
nbshell bar              # durchgehender Balken
nbshell island           # freistehende Insel, klappt zur Uhr zusammen
nbshell pill             # dieselbe Insel, bleibt aber offen
nbshell mode toggle      # reihum durch die drei Formen
nbshell edge top|bottom|toggle
nbshell open|close|toggle   # Insel festhalten, unabhaengig von der Maus

nbshell theme            # aktuelles Theme
nbshell theme gruvbox    # wechseln
nbshell themes           # alle auflisten
nbshell theme install [--force] <url|verzeichnis>
nbshell picker           # Themewahl aufklappen
nbshell next | prev      # ein Theme weiter

nbshell audio up | down  # Lautstaerke, fuer die Multimediatasten
nbshell audio mute
nbshell audio 40         # fest einstellen
nbshell audio panel      # Regler und Geraeteliste

nbshell launcher         # Anwendungsstarter (Alias: run)
nbshell find ghost       # zeigt, was er finden wuerde

nbshell notify           # Stand der Benachrichtigungen
nbshell notify dnd       # nicht stoeren
nbshell switch on        # DMS weicht (siehe „Der Umschaltmoment")
nbshell switch off       # zurueck zu DMS

nbshell tray             # was gerade im Tray steckt
nbshell osd test         # Einblendung ausprobieren
nbshell osd on | off

nbshell settings         # Optionsmenue (Mod+Comma nach dem Umstieg)
nbshell battery          # Ladestand, Restzeit, Profil
nbshell bat powersave    # Energieprofil wechseln
nbshell updates          # status, check, list, run
nbshell ai               # KI-Verbrauch (auch: refresh)
nbshell capture          # Aufnahme-Menue (screen, window, region, ocr, record)
nbshell procs            # Prozessliste; `nbshell procs top` als Text
nbshell power            # Power-Menue (auch: lock, logout, suspend)
nbshell clip             # Zwischenablage (toggle, list, clear)
nbshell cal              # Kalender (auch: next, sync, status)
nbshell plugins          # Bausteine auflisten (auch: reload)
nbshell popout wetter    # Popout eines Bausteins aufklappen
nbshell media playpause  # auch: next, previous, status

nbshell control          # Control Center
nbshell brightness up | down | 60

nbshell wallpaper on     # Hintergrundbild des Themes
nbshell wallpaper ~/bild.jpg   # festes Bild stattdessen

nbshell set fontSize 15
nbshell set rightWidgets '["sys","sep","battery"]'
nbshell config           # ganze Config zeigen
nbshell status
nbshell state            # was gerade offen ist (Popouts, Overlays)
```

Fuer niri:

```kdl
Mod+Shift+I hotkey-overlay-title="nbshell: Form der Leiste" {
    spawn "nbshell" "mode" "toggle";
}
Mod+Shift+T hotkey-overlay-title="nbshell: Themewahl" {
    spawn "nbshell" "picker";
}
Mod+D hotkey-overlay-title="nbshell: Anwendungsstarter" {
    spawn "nbshell" "launcher";
}
```

## Aussehen

### Drei Formen

`mode` kennt drei Werte — zwei Geometrien, drei Verhaltensweisen:

| | |
|---|---|
| `island` | freistehende Pille, die zur Uhr zusammenschrumpft und erst beim Ueberfahren alles zeigt |
| `pill` | dieselbe Pille, die aber **offen bleibt** — sie schwebt weiter ueber den Fenstern, ist nur nie leer |
| `bar` | durchgehender Balken ueber die volle Breite, der den Fenstern ihren Platz wegnimmt |

Die Pille ist kein dritter Bauzustand, sondern der **weggelassene**: sie ist die
aufgeklappte Insel, bei der der zugeklappte Zustand entfaellt. `exclusiveZone`
bleibt bei −1, sie schwebt also wie die Insel; nur der Nachlauf, der sonst
zuklappt, laeuft nie an.

`nbshell mode toggle` geht deshalb im Kreis statt hin und her:
`island → pill → bar → island`.

Danach bestimmen zwei Entscheidungen alles andere.

### Lesbarkeit statt Hoffnung

Ein Theme darf beliebige Farben mitbringen. `selection` ist bei manchen dunkel
(tokyo-night: `#292e42`), bei anderen **hell** (dos-moos: `#A5B5AB`). Wer
darauf einen festen Vordergrund malt, hat bei der Haelfte der Themes helle
Schrift auf hellem Grund — genau das ist im Optionsmenue passiert.

Deshalb wird gerechnet statt geraten, mit dem Kontrastverhaeltnis nach WCAG:

- `Theme.on(flaeche)` — der bessere von Vorder- und Hintergrund des Themes.
  Ein fester Helligkeitsschwellwert liegt bei mittelhellen Farben regelmaessig
  daneben, das Verhaeltnis nicht.
- `Theme.readable(farbe, flaeche, minimum)` — zieht die gewuenschte Farbe so
  weit ins Helle oder Dunkle, bis sie das Verhaeltnis erreicht. Die Farbe
  bleibt die des Themes, nur eben lesbar.

Beides greift ueberall dort, wo Text auf `selection` liegt (jede ausgewaehlte
oder ueberfahrene Zeile) und beim Akzent als Bausteinfarbe. Gemessen im
Optionsmenue mit dos-moos: 11,2:1 statt vorher kaum Unterschied.

### Zwei Dialekte

Omarchy-Themes gibt es in **zwei Palettenformaten**:

| | |
|---|---|
| alt | benannte Schluessel — `red`, `green`, `muted`, `dark_foreground` … |
| neu | ANSI-Nummern — `color0` … `color15`, `selection_background` … |

Die mitgelieferten sind der alte, frisch geholte meist der neue. nbshell liest
beide und rechnet Fehlendes aus: `mode` aus der Luminanz des Hintergrunds,
`lighter_background`, `selection`, `muted` und `dark_foreground` als Mischung
aus Vorder- und Hintergrund — dieselben Mischungen wie in omarchy2dms.

Wer nur einen Dialekt liest, bekommt beim anderen ein **halb gefuelltes**
Theme. Und weil die Vorgabewerte in `Theme.qml` ein vollstaendiges Theme sind,
sieht das nicht kaputt aus, sondern nur falsch — Hintergrund und Akzent
stimmen, die uebrigen Farben stammen vom Vorgabetheme.

Das gilt an **zwei** Stellen, und die zweite ist leicht zu vergessen:
`Theme.qml` faerbt die laufende Shell, `scripts/themes.sh` fuellt die
Farbkaestchen im Themewaehler. Lange konnte nur die erste beide Dialekte —
ein frisch geholtes Theme sah in der Vorschau deshalb anders aus als dasselbe
Theme mitgeliefert, obwohl beide nach dem Wechsel gleich aussahen. Auch hier
faellt es kaum auf, weil `background` und `accent` in beiden Dialekten gleich
heissen: nur die drei rechten Kaestchen waren leer.

**Die Farben kommen aus Omarchys `colors.toml`** — denselben Dateien, die
[omarchy2dms](https://github.com/nerdislb/omarchy2dms) schon fuer DMS umbaut,
hier ohne Umweg gelesen. Es gibt keine Farbrollen wie „surfaceContainerHighest",
sondern das, was auch ein Terminal kennt: Hinter- und Vordergrund, Akzent,
gedaempft, und die acht Farben. Ein Themewechsel faerbt damit Shell und
Terminal gleich.

**Die Masse sind Zellen, keine Pixel.** `cellW` und `cellH` kommen aus der
Schrift; Hoehen und Abstaende sind Vielfache davon. Deshalb sitzt alles auf
einem Zeichenraster, so wie in einer Statuszeile. Wer die Schriftgroesse
aendert, aendert die ganze Leiste mit — `nbshell set fontSize 15` genuegt.

Einstellbar in `config.json`: `theme`, `font`, `fontSize`,
`mode` (`island` | `pill` | `bar`), `edge`,
`gap`, `lines`, `padX`, `padY`, `radius`, `borderWidth`, `opacity`,
`widgetStyle` (`box` | `bracket` | `plain`), `widgetColor` (`text` | `accent`),
`widgetIcons`, `quietWidgets`, `widgetGap`, `islandCenter`, `osdInPill`,
`workspaceStyle` (`numbers` | `dots` | `pacman` | `invader`), `workspaceClassic`,
`barBorder`, `calendar`, `calendarInterval`,
`weatherPlace`, `weatherInterval`, `sysGpu`,
`collapseDelay`, `clockFormat`,
`titleLength`, `locale`, `wallpaper`, `wallpaperOverride`, `maxVolume` und die
vier Bausteinlisten.

## Themes — omarchy2dms, hier eingebaut

Umrechnen muss nbshell nichts: es liest Omarchys `colors.toml` direkt, es gibt
kein Zielformat mehr. Von [omarchy2dms](https://github.com/nerdislb/omarchy2dms)
bleibt damit nur das Suchen und Auflisten uebrig, und das erledigt
`scripts/themes.sh` in einem Aufruf — Name, Modus, fuenf Farben fuer die
Vorschau und das erste Wallpaper.

Wallpaper werden an drei Stellen gesucht: beim Theme selbst
(`<theme>/backgrounds/`), im Zwischenspeicher von omarchy2dms
(`~/.local/share/omarchy2dms/wallpapers/<theme>/`, den beide teilen) und unter
`~/.local/share/nbshell/wallpapers/<theme>/`.

### Themes dazuholen

```bash
nbshell theme install https://github.com/…/omarchy-<name>-theme
nbshell theme install ~/pfad/zum/theme
nbshell theme install --force <url>   # ein vorhandenes bewusst ersetzen
nbshell theme update          # selbst installierte per git pull
nbshell theme remove <name>
nbshell theme list            # mitgeliefert vs. selbst installiert
```

**Was schon da ist, wird nicht angefasst.** Frueher wurde erst geklont und
danach kommentarlos ersetzt — wer ein Theme zweimal holte, sah nichts davon,
und ein selbst geaendertes war weg. Jetzt kommt eine Meldung, und es passiert
nichts; `--force` ersetzt.

Verglichen wird dabei **ohne Trennzeichen und Grossschreibung**: `lasthorizon`
und `last-horizon` sind dasselbe Theme. Das Repo heisst nun mal anders als das
Verzeichnis, das Omarchy mitliefert — ohne diesen Vergleich stehen beide
nebeneinander in der Liste, mit derselben Palette und demselben Wallpaper.

Bringt ein Theme **keine `colors.toml`** mit -- und das gilt fuer alle aus der
Zeit vor Omarchys Umstellung --, wird die Palette aus seiner `alacritty.toml`
abgeleitet: Hinter- und Vordergrund direkt, hell/dunkel aus der Luminanz nach
WCAG, Fehlendes gemischt. Dieselbe Rechnung wie in omarchy2dms.

Geholt wird **erst in ein temporaeres Verzeichnis, ersetzt wird danach**. Der
umgekehrte Weg loescht ein vorhandenes Theme schon beim Tippfehler in der URL --
genau das ist mir hier einmal passiert.

Der Baustein `themes` zeigt das aktive Theme; ein Klick klappt die Liste mit
Farbproben auf, das Mausrad blaettert direkt durch, `nbshell picker` oeffnet
sie per Tastenkuerzel.

## Audio

Der Baustein `volume` zeigt die Lautstaerke; Mausrad regelt, Rechtsklick
schaltet stumm, ein Klick klappt Regler, Mikrofon und die Liste der Ausgaben
auf. Die Anbindung ist Quickshells Pipewire-Modul — kein `pactl` und kein
`wpctl` dazwischen.

Der Regler ist ein Balken aus Bloecken (`Widgets/LevelBar.qml`), 24 Zeichen
breit: gefuellt bis zum Wert, danach gedaempft. Klicken und Ziehen setzt ihn.

Fuer die Multimediatasten in niri:

```kdl
XF86AudioRaiseVolume allow-when-locked=true { spawn "nbshell" "audio" "up"; }
XF86AudioLowerVolume allow-when-locked=true { spawn "nbshell" "audio" "down"; }
XF86AudioMute        allow-when-locked=true { spawn "nbshell" "audio" "mute"; }
XF86AudioMicMute     allow-when-locked=true { spawn "nbshell" "audio" "micmute"; }
```

Ohne Beobachter (`PwObjectTracker`) bleiben Pipewires Knoten leer — die Daten
kommen erst, wenn jemand sie im Auge behaelt. Das ist der uebliche Stolperstein
bei Pipewire in Quickshell.

## Anwendungsstarter

`Mod+D` oder `nbshell launcher`. Tippen sucht, `↑↓` (oder `Ctrl-N`/`Ctrl-P`)
waehlt, Enter startet, Esc schliesst. Findet die Eingabe nichts, wird sie als
Befehl ausgefuehrt — wie in einem Terminal, nur ohne eines zu oeffnen.

Aufgebaut wie DMS' Spotlight: Suchzeile oben, darunter Zeilen mit Symbol,
Name, Beschreibung und einer Kennzeichnung (`APP` oder `TUI`). Programme ohne
eigenes Symbol bekommen ihren Anfangsbuchstaben in einem Kasten -- Quickshell
liefert mit `iconPath(name, true)` einen leeren Pfad statt des magentafarbenen
Karomusters fuer ein fehlendes Bild.

Ohne Eingabe steht oben, was am haeufigsten gestartet wurde. Die Zaehler
liegen in `~/.local/state/nbshell/usage.json` -- Gebrauchsspur, keine
Einstellung, und deshalb bewusst nicht in der Config.

Die Liste kommt von Quickshells `DesktopEntries`, das die .desktop-Dateien
aller XDG-Pfade schon eingelesen hat. Gesucht wird als Teilfolge mit
Zuschlaegen: Treffer am Wortanfang zaehlen mehr, aufeinanderfolgende noch
mehr, und ein Name, der direkt mit der Eingabe beginnt, gewinnt fast immer.
Zweitname und Beschreibung zaehlen nur halb — sonst draengt sich ein Programm
nach vorn, weil in seinem Fliesstext zufaellig die Buchstaben vorkommen.

Anwendungen mit `Terminal=true` bekommen eines: `$TERMINAL`, oder was in der
Config unter `terminal` steht. Ohne das faende ein Start von `htop` still
nicht statt.

Das Fenster nimmt sich die Tastatur exklusiv (`keyboardFocus: Exclusive`) --
sonst liesse sich nicht tippen, waehrend darunter ein Fenster den Fokus haelt.
Es gibt es genau einmal, nicht je Bildschirm: ein zweiter Starter waere ein
zweites Eingabefeld mit eigenem Zustand.

## Control Center

Der Baustein `control` zeigt in der Leiste, an welchem Netz du haengst — ein
reiner Knopf waere verschenkter Platz. Ein Klick klappt drei Abschnitte auf:

- **Helligkeit** als Balken. Gelesen wird aus `/sys/class/backlight`, gesetzt
  ueber logind (`SetBrightness`). Das ist der Weg ohne Zusatzpaket und ohne
  udev-Regel: logind erlaubt es jeder Sitzung, die gerade aktiv ist.
  `brightnessctl` waere ein weiteres Paket auf jedem neuen Rechner.
- **WLAN** an/aus, die staerksten acht Netze mit Signalbalken und Schloss.
  Klick verbindet, bei einem unbekannten verschluesselten Netz klappt eine
  Passwortzeile auf (Enter verbindet, Esc bricht ab). Ein Klick auf das
  verbundene Netz trennt.
- **Bluetooth** an/aus und die Geraete: verbundene zuerst, Klick verbindet
  oder trennt, ein unbekanntes wird gekoppelt. Akkustand steht dabei, wenn das
  Geraet ihn meldet.

Netz und Bluetooth kommen aus Quickshells eigenen Modulen — kein `nmcli`,
kein `bluetoothctl` dazwischen.

### Suchen

Beide Abschnitte haben rechts ein `[ suchen ]`. Waehrend gesucht wird, laeuft
dort ein Strich im Kreis; die Liste fuellt sich waehrenddessen.

Die zwei Funkstandards verhalten sich dabei unterschiedlich, und das merkt man:

- **WLAN.** Die API kennt keinen Einzelauftrag, nur den Dauerschalter
  `scannerEnabled`. Aus und wieder an stoesst also den naechsten Durchgang an.
  Fertig meldet niemand — weder Signal noch Zustand —, deshalb laeuft die
  Anzeige acht Sekunden auf einer Uhr. Solange das Popout offen ist, bleibt der
  Scanner an, damit die Liste aktuell bleibt; beim Zugehen geht er wieder aus.
- **Bluetooth.** Hier gibt es einen echten Zustand (`discovering`), angezeigt
  wird also nichts geraten. Von selbst hoert BlueZ nie auf, darum endet die
  Suche nach 30 Sekunden und spaetestens beim Schliessen des Popouts: eine
  laufende Suche haelt das Funkmodul wach und laesst Kopfhoerer stottern.
  Waehrend der Suche zeigt die Liste auch Geraete ohne Namen als blosse
  Adresse — den Namen liefern sie erst ein, zwei Sekunden spaeter, und wer sie
  bis dahin ausblendet, zeigt eine leere Liste, obwohl gerade etwas gefunden
  wurde.

**`discovering` ist der Zustand des Adapters, nicht der eigene.** BlueZ zaehlt
Suchen pro Programm: laeuft nebenher eine Einstellungs-App, steht im Popout
„sucht", obwohl wir nichts angefordert haben — und ein Stopp quittiert BlueZ
mit „No discovery started". Deshalb merkt sich `Bt.requested` getrennt, ob die
Suche von uns kommt; das Symbol zeigt den echten Zustand, der Knopf schaltet
nur die eigene Sitzung.

## Benachrichtigungen

Karten am rechten Rand, gegenueber der Leiste: Programmname, Zeit als Abstand
(„vor 3 min"), Titel, Text und die Knoepfe, die das Programm mitschickt. Ein
Klick blendet aus, ein Rechtsklick wirft weg, Ueberfahren haelt sie stehen.
**Dringendes bleibt** — rot umrandet und mit `!` —, bis man es wegklickt; so
sieht es die Spezifikation vor.

Der Baustein `notifications` zeigt die Anzahl, sein Popout das Archiv mit
„nicht stoeren" und „leeren". Rechtsklick auf die Zelle schaltet direkt stumm.

### Der Umschaltmoment

`org.freedesktop.Notifications` bekommt genau **ein** Prozess. Deshalb ist
nbshells Server **vorgabemaessig aus** — und das aus einem haerteren Grund als
„die beiden stoeren sich":

```
$ systemctl --user cat dms.service
[Service]
Type=dbus
BusName=org.freedesktop.Notifications
```

DMS gilt systemd erst dann als gestartet, wenn dieser Name auftaucht. Nimmt
nbshell ihn, haengt `dms.service` ewig in „activating" und wird schliesslich
als fehlgeschlagen neu gestartet — obwohl der Prozess laeuft und die Leiste da
ist. Umgekehrt gibt Quickshell den Namen von selbst frei und **greift auch von
selbst zu, sobald der andere ihn loslaesst**; ein Neustart ist dafuer nicht
noetig.

Umschalten heisst deshalb mehrere Dinge auf einmal, und dafuer gibt es einen
Befehl:

```bash
nbshell switch on             # DMS stoppen, Server uebernehmen, Binds umbiegen
nbshell switch on dauerhaft   # zusaetzlich maskieren
nbshell switch off            # alles zurueck
nbshell switch status
```

Er kuemmert sich um alles, was zusammengehoert:

1. **`dms.service` stoppen.** `disable` hilft dabei NICHT: DMS haengt ueber ein
   Drop-in an `niri.service`
   (`~/.config/systemd/user/niri.service.d/dms.conf`, `Wants=dms.service`) und
   kommt bei jeder Anmeldung wieder. Dauerhaft weg bleibt es nur mit `mask` --
   und das nur auf ausdrueckliche Ansage.
2. **Den Benachrichtigungsserver umlegen.**
3. **Den Autostart.** `systemd/nbshell.service` liegt seit `install.sh` bereit,
   wird aber erst hier eingeschaltet -- ueber ein Drop-in an `niri.service`
   (`Wants=nbshell.service`), dieselbe Stelle, an der DMS haengt. Eine EIGENE
   Datei, damit `dms.conf` unangetastet bleibt und der Rueckweg frei ist.
   **Ohne diesen Schritt startet nbshell nach dem Anmelden gar nicht** -- und
   mit maskiertem DMS waere der Bildschirm leer.
4. **Die Tastenkuerzel**, die bisher DMS gehoerten: `niri/nbshell-takeover.kdl`
   wird als letzter Include eingehaengt (mit Sicherung und `niri validate`
   davor) und biegt `Mod+Space` auf den Starter und `Mod+N` auf das
   Benachrichtigungsarchiv.

Die Takeover-Datei biegt inzwischen alles um, was nbshell kann:

| Taste | vorher DMS | jetzt |
|---|---|---|
| `Mod+Space` | spotlight | Anwendungsstarter |
| `Mod+N` | notification center | Benachrichtigungsarchiv |
| `Mod+V` | clipboard | Zwischenablage |
| `Super+X` | powermenu | Sitzungsmenue |
| `Mod+M`, `Ctrl+Alt+Entf` | processlist | Prozessliste |
| `Mod+Comma` | settings | Optionsmenue |
| `Mod+Y` | Wallpaper-Browser | Hintergrund-Karussell |
| `Mod+Alt+L` | lock | `lockCommand` (Vorgabe hyprlock) |
| `XF86AudioPlay/Next/Prev` | mpris | MPRIS-Anbindung |

**Was tot bleibt**, weil nbshell es nicht hat: `Mod+Shift+N` (Notizblock).

**Achtung Sperrbildschirm:** auf diesem Rechner ist *keiner* installiert.
`nbshell power lock` sagt das per Benachrichtigung, statt still nichts zu tun --
aber vor dem Umstieg gehoert `hyprlock` (oder etwas anderes) installiert.

## System-Tray

Der Baustein `tray` ist **eingeklappt voreingestellt**: dort steht dann nur ein
Pfeil mit der Anzahl (`▸3`). Fuenf bunte Programmsymbole dauerhaft in einer
Textleiste sind das Lauteste, was sie zu bieten hat. Ein Klick auf den Pfeil
klappt sie aus, `nbshell tray toggle` tut dasselbe, und der Zustand steht in der
Config -- er ueberlebt den Neustart.

Aufgeklappt zeigt er die Symbole der Programme, die sich per
StatusNotifierItem anmelden. Links startet, Mitte loest die zweite Aktion des
Programms aus, rechts oeffnet dessen Menue, das Mausrad wird durchgereicht --
genau das, was ein SNI-Programm erwartet. Ein Symbol, das sich als „passiv"
meldet, wird blasser statt zu verschwinden: fehlende Symbole verwirren mehr,
als sie Platz sparen.

Das ist die eine Stelle, an der eine Textoberflaeche nicht mit Text auskommt --
die Symbole kommen von den Programmen selbst.

**Der Tray vertraegt sich mit DMS.** Anders als bei den Benachrichtigungen
duerfen sich mehrere Anzeiger gleichzeitig anmelden; beide Leisten zeigen also
dieselben Symbole, ohne sich zu streiten.

Die Menues zeichnet `Widgets/MenuView.qml` als Liste: `[x]` fuer Haken, `(•)`
fuer eine Auswahl, `▸` fuer ein Untermenue. Untermenues klappen **an Ort und
Stelle** auf statt seitlich herauszufahren -- das spart ein zweites Fenster und
passt besser zu einer Oberflaeche, die sonst nur Zeilen kennt. Fuer die
Verschachtelung laedt die Datei sich selbst ueber ihren Pfad nach; sich direkt
zu verwenden geht in QML nicht, der Typ waere waehrend seiner eigenen
Definition noch nicht fertig.

## Power-Menue

`nbshell power` oder ein Tastenkuerzel. Sechs Zeilen mit je einem Buchstaben
davor -- `x` schaltet aus, ohne dass man zaehlen muss; Pfeile und Enter gehen
auch. Bewusst **ohne Rueckfrage**: das Menue selbst ist die Rueckfrage, und Esc
ist immer da.

Alles laeuft ueber `systemctl` und `niri msg action quit`. Der
Sperrbildschirm ist ein fremder (`lockCommand`, Vorgabe `hyprlock`) --
nbshell baut absichtlich keinen eigenen: ein Fehler darin sperrt dich aus dem
eigenen Rechner aus.

## Aufnehmen

`nbshell capture` — Omarchys Capture-Menue, uebernommen aus dem DMS-Plugin
[screenCapture](https://github.com/nerdislb/screen-capture): Bildschirm,
Fenster, Bereich, Texterkennung, Bildschirmaufnahme, letztes Bild bearbeiten,
Ordner oeffnen. Der Baustein `capture` zeigt waehrend einer Aufnahme die
Laufzeit in Rot; Rechtsklick startet und stoppt sie direkt.

Die Auswahl macht **niris eigene Screenshot-Oberflaeche**, nicht slurp: sie
friert das Bild ein UND kennt die Fenster -- unter niri kommt sonst niemand an
Fensterkoordinaten. Alles danach (warten, melden, Editor, OCR, wf-recorder)
macht `scripts/capture.sh`, unveraendert aus dem Plugin uebernommen; das ist
Shell-Arbeit und laesst sich so auch direkt auf eine Taste legen.

Nach der Wahl schliesst das Menue **sofort** und wartet 250 ms, bevor es
ausloest: niri friert das Bild ein, sobald die Aktion ankommt, und ohne Pause
haengt das halb verschwundene Menue mit im Screenshot.

## KI-Verbrauch

Der Baustein `ai` zeigt ein Symbol, das sich **von unten fuellt** -- so weit,
wie das laufende Zeitfenster verbraucht ist. Das Popout nennt Prozent, Fenster
und wann es zurueckgesetzt wird; Klick auf das Symbol aktualisiert.

Die Zahlen holt ein fremdes Helferskript (`get-provider-usage` aus dem
DMS-Plugin `aiOverviewControl`). Es ist reines Bash und funktioniert weiter,
auch wenn DMS nicht mehr laeuft -- die Dateien liegen ja noch da. Nachgebaut
wird es nicht: es kennt die Anmeldung an mehrere Anbieter, und das ist fremde
Arbeit. Fehlt es, bleibt der Baustein still.

Zwei Dinge, die beim Fuellen entscheidend sind (aus `aiFillWidget`
uebernommen):

- **Nicht ueber `font.pixelSize` normieren.** Jedes Zeichen bemalt einen
  anderen Anteil seiner Zeile; gleiche Groesse ergibt verschieden grosse
  Symbole. Vorgegeben wird eine Ziel-*Tintenhoehe*, die Schriftgroesse folgt
  daraus. Die Messprobe braucht eine eigene `TextMetrics` mit fester Groesse,
  sonst dreht sich die Bindung im Kreis.
- **`tightBoundingRect` zaehlt ab der Grundlinie**, ein `Text` dagegen ab
  seiner Oberkante. Dazwischen liegt die Oberlaenge — die kommt aus
  `FontMetrics.ascent`. `baselineOffset` taugt nicht, das ist 0, und die
  Fuellung landet ausserhalb des Zeichens.

## Terminalfarben und Fensterrahmen mitfaerben

Ein Themewechsel hoert nicht an der Leiste auf. nbshell schreibt bei jedem
Wechsel zwei Dateien:

- `~/.config/niri/nbshell-colors.kdl` — Fensterrahmen, Fokusring,
  Tab-Anzeiger und Einfuegemarke. `nbshell switch on` haengt sie als Include
  hinter DMS' eigenen, damit sie gewinnt.
- `~/.config/ghostty/themes/nbcolors` (die 16 ANSI-Farben plus Hinter-
und Vordergrund, direkt aus der `colors.toml`) und ruft danach
`~/.config/nbshell/theme-hook.sh` auf, falls es die gibt -- mit Themename und
Modus als Argumenten. Alles Weitere (btop, fuzzel, was auch immer) gehoert
dorthin und nicht in die Shell.

In ghostty muss `theme = nbcolors` stehen; `nbshell switch on` biegt die Zeile
um (und `switch off` zurueck auf `dankcolors`, das matugen fuer DMS schreibt).

## Updates

Der Baustein `updates` zeigt ein Symbol und die Zahl offener Systemupdates --
und **nur dann**, wenn es welche gibt: eine Null, die man taeglich liest, ist
Rauschen. Klick oeffnet die Liste (Paket, alte, neue Version), Rechtsklick
startet die Aktualisierung.

Das Symbol macht es wie DMS: waehrend der Pruefung dreht sich ein Pfeilkreis
(die Zahl waere in dem Moment die alte), sonst steht dort ein Pfeil nach unten
und daneben die Anzahl.

Symbole kommen aus der Nerd-Font-Schrift und laufen ueber `Widgets/Glyph.qml`.
Das misst, **wie viel seiner Zeile ein Zeichen wirklich bemalt**, und rechnet
daraus die Schriftgroesse fuer die gewuenschte Hoehe. Ohne diesen Umweg sind
zwei Symbole mit derselben `pixelSize` verschieden gross -- ein Pfeil fuellt die
Zeile fast aus, ein Punkt sitzt winzig in der Mitte. Derselbe Trick steckt im
KI-Baustein, dort fuer den Fuellstand.

Bei der Wahl des Zeichens zaehlt nur, wie es bei 14 px aussieht: der erste
Versuch (`nf-fa-download`) hatte so feine Striche, dass in der Leiste ein
Fleck uebrig blieb. Jetzt steht dort das fette `nf-md-download`.

Gesucht wird ohne root und **ohne die Systemdatenbank anzufassen**: pacman
synchronisiert unter `fakeroot` in eine eigene Datenbank, und `-Qu` vergleicht
dagegen -- derselbe Trick wie in `checkupdates`. Ein `pacman -Sy` auf die echte
Datenbank waere die uebliche Falle: danach steht das System auf einem halben
Stand, und der naechste Paketwunsch zieht Bibliotheken in Versionen, die zum
Rest nicht passen.

Zwei Dinge, ueber die man dabei stolpert:

- **`--disable-sandbox` ist Pflicht.** pacman 7 sperrt sich per Landlock ein und
  wechselt auf den Benutzer `alpm`; beides scheitert unter fakeroot, der
  Abgleich bricht ab -- und die Pruefung meldet stumm null Updates.
- **Aktualisiert wird im Terminal**, nicht im Hintergrund: `paru` fragt nach dem
  Passwort und will bestaetigt werden. Ohne Fenster haengt es unsichtbar an der
  Eingabe. Ein Systemupdate, das in einer Leiste stillschweigend durchlaeuft,
  waere ohnehin unheimlich.

AUR-Updates kommen von `paru -Qua` (oder `yay`), Repo-Updates aus der eigenen
Datenbank. Geprueft wird alle vier Stunden (`updateInterval`) und beim Start
einmal nach einer Minute -- nicht sofort, damit die Anmeldung nicht mit einem
Datenbankabgleich anfaengt.

## Leistungsanzeige

Der Baustein `sys` zeigt in der Leiste CPU und Speicher. Ein Klick klappt die
Einzelheiten auf:

- **Prozessor** — Modell, Auslastung als Balken, Takt, die drei Lastmittel,
  Laufzeit und jeder Kern einzeln.
- **Speicher** — RAM, Swap, wie viel davon Cache ist, dazu die Wurzelpartition.
- **Temperatur** — CPU (das Paket, nicht die Kerne), Gehaeuse, SSD, Chipsatz,
  WLAN und der heisseste Kern. Ab 80 °C gelb, ab 90 °C rot.
- **Luefter** — Drehzahl, oder „aus", wenn sie stehen. Dass sie stehen, ist
  auch eine Auskunft.
- **Grafik** — Name, Auslastung, Speicher und Temperatur.

Zwei Entscheidungen dahinter:

- **Gemessen wird nur, solange jemand hinsieht.** Die Zelle in der Leiste liest
  `/proc/stat` und `/proc/meminfo` direkt in QML — das kostet nichts. Alles
  Weitere macht `scripts/sysinfo.sh`, und der laeuft erst, wenn das Popout
  offen ist.
- **`nvidia-smi` weckt die Grafikkarte.** Auf einem Optimus-Notebook haelt ein
  Aufruf alle zwei Sekunden die dedizierte Karte wach und kostet Laufzeit.
  Deshalb fragt nur das Popout, nie die Leiste — und `sysGpu: false` schaltet
  es ganz ab.

Die Sensoren werden **gefiltert, nicht gesammelt**: `/sys/class/hwmon` meldet
hier zwei Dutzend Werte, von denen die meisten Dubletten sind. `dell_smm`
liefert acht unbeschriftete Temperaturen, die als CPU, Chipsatz und Gehaeuse
schon dabei sind — seine Luefter sind aber die einzige Quelle, also faellt nur
sein Temperaturteil weg.

## Akku und Energieprofil

Der Baustein `battery` zeigt in Ruhe den Ladestand, **unter der Maus die
Restzeit** -- die will man selten, aber dann sofort. Ein Klick oeffnet die
Energieeinstellungen: Ladestand als Balken, Zustand, Restzeit, Gesundheit und
Leistung, darunter die Energieprofile zum Umschalten.

Die Profile kommen von **`tuned`**, nicht von `power-profiles-daemon`. Die
beiden schliessen sich aus, und auf diesem Rechner laeuft tuned -- wer das
falsche fragt, bekommt gar keine Antwort. (Quickshells eigenes `PowerProfiles`
spricht nur mit ppd, deshalb ist es hier nicht benutzt.)

tuned kennt ueber 30 Profile, von SAP HANA bis Realtime. In der Leiste steht
eine kurze Auswahl, die auf einem Notebook Sinn ergibt (`powerProfiles` in der
Config); alles andere bleibt `tuned-adm` vorbehalten.

## Prozessliste

`nbshell procs` — der Ersatz fuer DMS' `Mod+M`. Aufgebaut wie der Starter:
Filterfeld oben (Name oder PID), darunter die Liste mit PID, CPU, RAM, RSS und
Namen in festen Spalten. `Ctrl-S` wechselt die Sortierung, `Ctrl-K` beendet den
gewaehlten Prozess (SIGTERM), `Ctrl-Shift-K` erzwingt es (SIGKILL).

Die Tasten liegen bewusst auf `Ctrl`: das Filterfeld hat den Fokus, und ein
blosses `k` soll dort ein Buchstabe bleiben.

Gelesen wird mit `ps` -- es steht auf jedem System und kennt die Prozentwerte
schon. Abgefragt wird **nur, solange die Liste offen ist**; ein Zaehler, der im
Hintergrund alle zwei Sekunden ein `ps` startet, waere reine Verschwendung.

## Kalender

Ein Klick auf die Uhr klappt ihn auf: Monatsgitter mit Kalenderwochen, ein
Punkt unter jedem Tag, an dem etwas ansteht, darunter die Termine des
gewaehlten Tages. Mausrad blaettert durch die Monate, `[ heute ]` kommt
zurueck. Ohne Popout: `nbshell cal next`.

**Die Shell spricht mit keinem Anbieter.** Sie liest, was schon auf der Platte
liegt — und zwar durch **khal**, nicht selbst:

```
Google / iCloud / ICS-Abo
        │  vdirsyncer (systemd-Timer, alle 15 min)
        ▼
~/.local/share/calendars/…      ← ganz normale Ordner mit .ics-Dateien
        │  khal list --json …
        ▼
nbshell
```

Der Umweg ueber khal ist der Punkt: **Wiederholungen**. Ein „jeden zweiten
Dienstag, ausser am 24.12." steht als RRULE in der Datei und muss ausgerechnet
werden. khal kann das; ein Leser in QML koennte es nicht.

Google haengt damit genauso dran wie alles andere — in `~/.config/vdirsyncer/config`
als Speicher eintragen, in `~/.config/khal/config` den Ordner als Kalender.
Wer das schon fuer DMS eingerichtet hat, muss nichts tun: es sind dieselben
Ordner.

Drei Dinge, ueber die man dabei stolpert:

- **khal versteht Datumsangaben nur in dem Format, das in seiner Config
  steht.** Ein ISO-Datum quittiert es mit „Could not parse". `calendar.sh`
  liest darum `dateformat` aus der Config und rechnet hin und zurueck.
- **khal schreibt pro Tag eine eigene JSON-Liste**, nicht eine grosse — und
  wiederholt einen mehrtaegigen Termin auf jedem Tag, den er beruehrt. Fuer
  die Punkte im Gitter ist das praktisch, fuer die Liste nicht: doppelte
  fallen im Dienst raus.
- **Geladen wird ein Fenster um den angezeigten Monat, kein Jahr.** khal
  braucht fuer 400 Tage rund fuenf Sekunden, fuer 70 eine halbe. Wer
  blaettert, loest ein neues Fenster aus.

`[ abgleichen ]` stoesst vdirsyncer an (ueber dessen systemd-Unit, damit nicht
zwei Abgleiche nebeneinander laufen) und liest acht Sekunden spaeter neu.
Abschalten: `calendar: false`.

## Zwischenablage

Der Baustein `clipboard` zeigt die Anzahl, sein Popout den Verlauf; Klick
kopiert zurueck, Rechtsklick wirft einen Eintrag weg. Die ersten neun sind
nummeriert.

Ohne `cliphist` und ohne zweiten Dienst: `wl-paste --watch` meldet jede
Aenderung, der Verlauf liegt als JSON in `~/.local/state/nbshell/`. Der
Wachhund schickt jeden Eintrag **base64-kodiert in einer Zeile** -- sonst
zerfiele ein mehrzeiliger Text in lauter Einzelmeldungen. Zurueck kommt er
ueber `decodeURIComponent(escape(Qt.atob(...)))`, weil `Qt.atob` byteweise
dekodiert und Umlaute sonst zerbroeseln (geprueft mit „Grueße, Öl, Straße").

## Medien

Der Baustein `media` zeigt Interpret und Titel des laufenden Players. Klick
spielt und pausiert, Mausrad blaettert, Rechtsklick stoppt. Laufen mehrere
Player, gewinnt der spielende, sonst der zuletzt benutzte -- ohne diese Regel
greifen die Medientasten mal ins Leere, mal in den falschen Player.

## Einblendung (OSD)

Wer an Lautstaerke, Mikrofon oder Helligkeit dreht, sieht kurz einen Kasten
mit Balken und Wert — auch dann, wenn die Leiste gerade zugeklappt ist. Sie
erscheint immer **gegenueber der Leiste**: steht die Insel unten, blendet sie
oben ein. Sonst legen sich die beiden uebereinander.

Wer den passenden Regler schon offen vor sich hat, bekommt sie nicht: das
Audio-Popout unterdrueckt die Lautstaerke-Einblendung, das Control Center die
der Helligkeit.

Einstellbar: `osd` (an/aus) und `osdTimeout` in Millisekunden. Zum Ausprobieren
`nbshell osd test`.

### In der Pille

In der Pille gibt es kein zweites Fenster: **die Leiste wird selbst zur
Einblendung**. Sie schrumpft auf Kuerzel, Balken und Wert zusammen und geht
danach zurueck — statt dass am gegenueberliegenden Rand etwas aufblinkt.

Das kostet fast nichts, weil die Pille schon alles dafuer hat: zwei Reihen, die
einander ueberblenden, und einen Rahmen, dessen Breite mitlaeuft. Es kommt eine
dritte Reihe dazu, dieselben drei Teile wie im eigenen Fenster.

Nur in der Pille. Die Insel ist meistens zugeklappt — sie muesste erst
aufgehen —, und der Balken ist bildschirmbreit, da waere die Verwandlung keine.
In beiden erscheint weiterhin das eigene Fenster. `osdInPill: false` schaltet
es auch in der Pille zurueck.

Die Idee stammt aus [ChillPill-Shell](https://github.com/LUCKYS1NGHH/ChillPill-Shell),
deren ganze Oberflaeche so funktioniert: eine Pille, die zu allem wird, was sie
gerade zeigt — Control Center, Starter, Zwischenablage. **Nachgebaut, nicht
uebernommen**: ChillPill steht unter GPL-3.0, nbshell unter MIT.

Nicht uebernommen habe ich den Rest davon. Alle Popouts in die Leiste zu
verlegen wuerde zwar viel wegraeumen (`popoutCount`, `popoutHover`, den
Tastaturfokus-Tanz mit der Layer-Flaeche), aber die Popouts verloeren ihren
Anker an der Zelle — der Kalender klappt unter der Uhr auf, nicht in der Mitte.

Die ersten anderthalb Sekunden nach dem Start bleibt sie stumm — dort setzen
sich die Werte erst, und ohne die Sperre blitzte sie bei jedem Neustart auf.

## Hintergrundbild

`nbshell wallpaper pick` (nach dem Umstieg `Mod+Y`) blaettert durch die Bilder
des aktuellen Themes -- als Streifen am unteren Rand, `←→` blaettert, `Enter`
uebernimmt, `r` stellt das Bild wieder her, das das Theme selbst mitbringt,
`Esc` nimmt zurueck. Beim Blaettern wird das Bild **sofort gesetzt**: man sieht
es in voller Groesse hinter dem Streifen, statt aus einem Vorschaubild raten zu
muessen.

Die Liste wird bei jedem Oeffnen frisch gelesen, bewusst ohne Zwischenspeicher
-- genau der hat in der Vorlage (`themeWallpaper`) die Auswahl lahmgelegt: die
Pfeiltasten gingen, Enter nahm den alten Stand.

Zwei Stellen muessen dabei zusammenpassen, sonst springt die Auswahl beim
Blaettern zurueck: die Liste wird **nur beim Themewechsel** neu gelesen (nicht
bei jeder Config-Aenderung -- das Karussell schreibt beim Blaettern ja selbst
hinein), und **nur die erste Liste nach dem Oeffnen** bestimmt, wo der Rahmen
steht. Danach gehoert die Auswahl den Pfeiltasten.

**Die Wahl gilt fuer das Theme, nicht fuer immer.** Vorher blieb ein einmal
gewaehltes Bild bei jedem Themewechsel stehen -- und weil der Hintergrund das
Auffaelligste am Bildschirm ist, sah es aus, als taete der Wechsel gar nichts.
Gemerkt wird deshalb je Theme (`wallpaperByTheme`); wer zurueckwechselt,
bekommt sein Bild wieder, und `r` im Karussell loescht die Merkung fuer das
aktuelle Theme.

### Unschaerfe in der Uebersicht

niris Uebersicht (`Mod+Tab`) zeigt hinter den Arbeitsflaechen einen
**Backdrop** -- und dort landet jede Hintergrundflaeche, die per Layer-Regel
dafuer markiert ist. **Weichzeichnen kann niri dabei nicht selbst**: es zeigt
nur, was auf der Flaeche liegt. Deshalb dieselbe Loesung wie in DMS -- nbshell
haelt eine zweite, fertig verwischte Kopie des Bildes bereit:

```kdl
layer-rule {
    match namespace="nbshell:wallpaper-blur"
    place-within-backdrop true
}
```

Die Regel steht in `nbshell-takeover.kdl`, die Kopie entsteht mit
`MultiEffect`. Im Alltag sieht man sie nie -- sie liegt hinter der scharfen
Flaeche, und erst die Uebersicht holt sie hervor. Abschaltbar ueber
`wallpaperBlur`, Staerke ueber `wallpaperBlurAmount` (Vorgabe 64).

`nbshell wallpaper on` haengt den Hintergrund ans Theme: jedes Omarchy-Theme
bringt seine Bilder mit, ein Themewechsel blendet auf das neue um. Ein festes
Bild geht auch — `nbshell wallpaper ~/bild.jpg`, und `nbshell wallpaper set ""`
gibt wieder dem Theme das Wort.

**Voreingestellt ist es aus.** DMS malt seinen Hintergrund auf dieselbe
Wayland-Ebene; solange beide laufen, wuerden sie sich abwechselnd ueberdecken.

Ueberblendet wird ueber zwei Bildflaechen: die verdeckte laedt das neue Bild
und wird erst eingeblendet, wenn es steht — sonst blitzt beim Wechsel Schwarz
durch.

## Popouts

**Solange eines offen ist, klappt die Insel nicht zu.** Ein Popout ist ein
eigenes Fenster — wer aus der Leiste hinunter in die Liste faehrt, hat die
Leiste damit verlassen, und die Insel wuerde ihm unter der Hand wegklappen,
mitten im Auswaehlen. Ein laengerer Nachlauf hilft dagegen nicht, er verschiebt
es nur; die Leiste sieht deshalb auf `Runtime.popoutCount` und
`Runtime.popoutHover`. Erst wenn das letzte Popout zu ist, laeuft der Nachlauf
(`collapseDelay`, 600 ms) wieder an.

Damit der Zaehler stimmt, meldet sich eine Zelle beim Verschwinden ab: faellt
sie weg, waehrend ihr Popout offen ist — geaenderte Bausteinliste, neu geladene
Shell —, bliebe er sonst oben stehen und hielte die Insel fuer immer offen.

Ein Popout ist ein echtes Wayland-Popup (`PopupWindow`), kein zweites
Layer-Fenster: der Kompositor kennt die Beziehung zur Leiste, haelt es an der
richtigen Stelle und beendet den Griff selbst, sobald man daneben klickt. Ein
nachgebautes Overlay muesste das alles von Hand tun — samt bildschirmgrosser,
unsichtbarer Klickflaeche.

Ein Baustein bekommt eines, indem er `popout` setzt:

```qml
Cell {
    text: "…"
    popout: Component {
        Column {
            property var closePopout: null   // wird gesetzt, wenn es aufgeht
            …
        }
    }
}
```

Das Fenster entsteht erst, wenn ein Baustein wirklich eines hat, und der Inhalt
erst beim Aufklappen.

**Schliessen** geht auf drei Wegen, und keiner davon verlaesst sich auf den
Kompositor:

1. **Maus weg.** Verlaesst der Zeiger Popout *und* Zelle, geht es nach
   `popoutLeaveDelay` (2,5 s) zu. Das ist der Weg, der in der Praxis greift --
   wer woanders hinklickt, bewegt vorher die Maus dorthin.
2. **Fensterwechsel.** Wer in ein anderes Fenster klickt, bekommt vom
   niri-Ereignisstrom ein `WindowFocusChanged`; dann gehen alle Popouts zu.
3. **Esc**, solange die Leiste den Tastaturfokus hat.

Warum nicht einfach ein Popup-Griff (`grabFocus`)? Der wird hier zwar
angenommen, aber **nicht beendet, wenn man daneben klickt** -- das Popout
bliebe stehen. Und ein Griff hat eine Bedingung, die leicht zu uebersehen ist:
die Layer-Flaeche darunter muss ueberhaupt Tastatur annehmen duerfen. Steht die
Leiste auf `keyboardFocus: None`, lehnt der Kompositor ihn ab und das Popout
erscheint **gar nicht erst**, lautlos. Umgestellt wird deshalb schon beim
Ueberfahren einer Zelle mit Popout; Zellen ohne Popout melden sich nicht, damit
ein Klick auf die Arbeitsflaechen dem Fenster darunter nicht die Tastatur
wegzieht. Den Griff nimmt sich nur noch das Control Center -- dort wird ein
WLAN-Passwort getippt.

## Optionsmenue

`nbshell settings` (nach dem Umstieg `Mod+Comma`) — die haeufigen Schalter
sichtbar statt in der `config.json`: Rand, Form, Bausteinstil,
Schriftgroesse, Hoehe, Abstaende, Ecken, Rahmen, Deckkraft, Nachlauf sowie
Hintergrundbild, Einblendung, Benachrichtigungsserver, Zwischenablage und
Terminalfarben — gegliedert in LEISTE, AUSSEHEN, VERHALTEN und DIENSTE.
Dazu gehoert auch, in welcher Ecke die Benachrichtigungen aufgehen
(`notifyCorner`: auto, oben, unten) und wie lange eine Karte steht.

Eine Zeile oeffnet statt zu aendern: **„Bausteine anordnen …"** fuehrt mit
Enter in den Editor aus dem naechsten Abschnitt.

**Farbe der Bausteine** schaltet zwischen dem normalen Vordergrund (`text`) und
dem Akzent des Themes (`accent`). Warnfarben bleiben davon unberuehrt -- ein
leerer Akku ist rot, egal was hier steht.

Die gedaempfte Fassung wird dabei erst zum Hintergrund gezogen und **danach**
auf Lesbarkeit geprueft. Nur `readable(accent, …)` gaebe auf dunklem Grund
einfach wieder den Akzent zurueck -- Nebensaechliches und Wichtiges saehen
gleich aus, und die Abstufung in der Leiste waere weg.

**Rahmen um die Leiste** (`barBorder`) laesst sich abschalten, fuer Insel wie
Balken. Zellen, Popouts und Menues behalten ihren eigenen Rahmen;
`borderWidth` bestimmt weiterhin dessen Staerke.

Bewusst **kein Formular mit Eingabefeldern**: jede Zeile ist eine Liste von
Werten, durch die `←→` blaettert (Mausrad und Klick gehen auch). Das laesst
sich blind bedienen und braucht keine Pruefung von Eingaben. Geschrieben wird
sofort — die Leiste aendert sich beim Zusehen, weil die Config beobachtet wird.

Was hier fehlt (Bausteinlisten, Schrift, Themepfade), bleibt in der
`config.json`; die Datei ist weiterhin die vollstaendige Oberflaeche.

## Bausteine anordnen

`nbshell modules` — links die vier Gruppen mit ihrem Inhalt, rechts der
Vorrat. `↑↓` waehlt, `←→` verschiebt innerhalb der Gruppe, `Shift+←→` in die
Nachbargruppe, `x` wirft raus, `Tab` wechselt in den Vorrat, `Enter` haengt
von dort an. Das ist, was in der DankBar das Ziehen und Ablegen macht, nur mit
Tasten.

Damit loest sich auch die Frage „warum ist die Uhr nicht mittig": mittig steht
die **Mittelgruppe als Ganzes**. Liegt noch etwas anderes darin (die Medien
etwa), sitzt die Uhr eben daneben — hier laesst sie sich in einem Zug
woanders hinlegen.

## Bausteine

`clock`, `workspaces`, `window`, `sys`, `battery`, `layout`, `themes`,
`volume`, `control`, `tray`, `notifications`, `clipboard`, `media`, `capture`,
`ai`, `updates`, `sep`.

Vier Listen sagen, was wo steht:

```json
"collapsedWidgets": ["clock"],
"leftWidgets":  ["workspaces", "sep", "window"],
"centerWidgets": ["clock"],
"rightWidgets": ["sys", "sep", "layout", "battery"]
```

`collapsedWidgets` ist die zugeklappte Insel. Die anderen drei sind der
Balken — und die aufgeklappte Insel zeigt sie hintereinander.

### Arbeitsflaechen

Vier Stile, `workspaceStyle` in der Config oder **Rechtsklick** auf den
Baustein -- der geht reihum durch:

| | |
|---|---|
| `numbers` | die Nummern, unterstrichen ist die aktive (Vorgabe) |
| `dots` | dicker Punkt aktiv, kleine Punkte fuer die uebrigen |
| `pacman` | dieselben Punkte, auf der aktiven sitzt Pac-Man und kaut |
| `invader` | dieselben Punkte, auf der aktiven ein Space Invader |

Die beiden Figuren arbeiten gleich: eine Reihe Punkte, der aktive ist verdeckt
-- da steht die Figur. Unterschiedlich ist nur die Zeichnung. Pac-Man dreht
sich in die Laufrichtung (dafuer muss der vorige Index gemerkt werden, aus dem
aktuellen Zustand allein ist sie nicht ablesbar), der Invader bleibt aufrecht
und wechselt zwischen seinen zwei Bildern -- so lief es im Original auch.

Pac-Man ist gelb und der Invader gruen, sonst sind es keine.
`workspaceClassic: false` holt beide stattdessen aus der Palette des Themes.

Die Punkte sitzen auf dem Zeichenraster (`cellW`, `cellH`), nicht auf festen
Pixeln: wer die Schriftgroesse aendert, aendert sie mit.

Uebernommen vom Vorgaenger
[workspace-pills](https://github.com/nerdislb/workspace-pills), der dasselbe
als DMS-Plugin machte.


### Symbole

Vor dem Text steht ein Zeichen aus der Nerd-Font-Schrift: Tacho und Stapel fuer
Last und Speicher, Glocke fuer Meldungen, Lautsprecher, WLAN, Akku, Tastatur,
Palette. **`widgetIcons: false` schaltet alle ab** — dann steht wieder das
Kuerzel da (`VOL 16%`, `MSG 2`), und die Leiste ist eine reine Textzeile.
Deshalb hat jeder Baustein neben `icon` auch ein `label`: ohne das bliebe von
der Lautstaerke eine nackte Zahl uebrig, die neben der Uhr nichts mehr bedeutet.

Die Zeichen stehen gesammelt in `Common/Icons.qml`. Zwei Dinge, die dabei
zaehlen:

- **Ein Zeichen wird nach seinem Aussehen bei 14 px gewaehlt, nicht nach seinem
  Namen.** `nf-md-cpu-64-bit` heisst richtig, ist in der Leiste aber ein
  dunkler Klecks — die Innenzeichnung des Chips faellt unter die Aufloesung.
  Ein Tacho tut es. Genauso beim Updater: `nf-fa-download` hat zu feine
  Striche, das fette `nf-md-download` steht.
- **Die Groesse steckt nicht in `pixelSize`.** Jedes Zeichen bemalt einen
  anderen Anteil seiner Zeile; bei gleicher Schriftgroesse ist der eine Pfeil
  fast zeilenhoch und der andere ein Punkt in der Mitte. `Widgets/Glyph.qml`
  misst die tatsaechliche Hoehe der Zeichnung bei einer Probegroesse und rechnet
  daraus zurueck. `Widgets/IconText.qml` setzt Zeichen und Text nebeneinander,
  jedes in einem eigenen Kaestchen auf Zeilenhoehe — die Kinder eines
  Positionierers duerfen keine Anker haben.

### Die Mitte ist die Mitte

Mittig steht die **Mittelgruppe**, nicht die Uhr — liegt noch etwas anderes
darin, sitzt die Uhr eben daneben. Wo genau die Gruppe landet, ist in den zwei
Modi verschieden geloest:

- **Im Balken** gibt es freie Breite. Die beiden Luecken werden so verteilt,
  dass die Mittelgruppe auf der Bildschirmmitte sitzt, auch wenn links und
  rechts unterschiedlich viel steht.
- **In der Insel** gibt es keine freie Breite — sie ist genau so breit wie ihr
  Inhalt. Die Mitte wird deshalb ueber die Luecken erzwungen: die schmalere
  Seite bekommt den Unterschied dazu. Damit sitzt die Mittelgruppe in der Mitte
  der Insel, und weil die Insel mittig auf dem Bildschirm steht, sitzt die Uhr
  dort — ausgeklappt wie zugeklappt.

Der Preis in der Insel: sie wird um den Unterschied der beiden Aussengruppen
breiter. `islandCenter: false` nimmt beides zurueck (gleich grosse Luecken, die
Uhr wandert).

### Wie eng die Leiste steht

Zwei Werte, beide in **Zeichen** und beide im Optionsmenue unter AUSSEHEN:

| | |
|---|---|
| `padX` | Innenabstand einer Zelle, links wie rechts |
| `widgetGap` | Abstand zwischen zwei Bausteinen |

Zwischen zwei Texten liegen also `padX + widgetGap + padX` Zeichen — bei den
Vorgaben (1 und 1) sind das drei, was luftig wirkt. `0.5` und `0.5` ergibt zwei
und sieht deutlich kompakter aus, ohne dass etwas zusammenlaeuft. Bei `0` und
`0.5` beruehren sich Zahlen und Symbole fast.

Netz und Theme zeigen ihren Namen **nur ohne Symbole**: das WLAN-Symbol sagt
schon, ob und wie man haengt, und der Name steht im Popout. Mit `widgetIcons:
false` kommen beide Namen zurueck, sonst waere die Zelle leer.

### Feste Slots und stille Bausteine

Zwei Kleinigkeiten aus Omarchys Leiste, die den Unterschied machen, ob eine
Leiste ruhig steht:

- **`slotChars` reserviert Platz in Zeichen.** Ohne das wandert die halbe
  Leiste, sobald die Lautstaerke von 9 % auf 100 % geht oder der Akku beim
  Ueberfahren auf die Restzeit umschaltet. Reserviert wird der laengste Fall.
- **`quiet` blendet aus, was gerade nichts zu sagen hat** — keine Meldung,
  keine Aufnahme, leere Ablage. Beruehrt die Maus die Leiste, kommen die
  Bausteine gedaempft hervor. Fuenf Symbole, die dauerhaft „nichts" anzeigen,
  sind das Lauteste an einer Textleiste. Abschalten: `quietWidgets: false`.

Der Akku waehlt sein Zeichen nach dem Ladestand (`Icons.battery(percent)`),
beim Laden steht der Blitz da. Die Reihe `F0079..F0082` ist dabei "voll, 10 %,
20 % … 90 %" — also nicht nach Prozent sortiert, daher die Fallunterscheidung
statt einer Rechnung auf dem Zeichencode.

## Eigene Bausteine (Plugins)

Ein Baustein muss nicht in der Shell stehen. Ein Verzeichnis unter
`~/.config/nbshell/plugins` reicht:

```
~/.config/nbshell/plugins/wetter/
    manifest.json
    BarWidget.qml
```

```json
{
  "id": "wetter",
  "name": "Wetter",
  "description": "Temperatur am Ort",
  "category": "Plugin",
  "entry": "BarWidget.qml"
}
```

Danach `nbshell plugins reload`, und der Baustein steht im Anordnen-Menue im
Vorrat — mit `·plugin` dahinter. `nbshell plugins` listet alles auf, Eingebautes
und Nachinstalliertes nebeneinander.

Mitgeliefert werden zwei: **`beispiel`** als Vorlage (zaehlt Klicks, sonst
nichts) und **`wetter`** — Temperatur in der Leiste, Einzelheiten und fuenf
Tage im Popout. Der Ort steht in der Config:

```bash
nbshell set weatherPlace Graz
nbshell popout wetter          # aufklappen, auch fuer eine Taste in niri
```

**Das Wetter-Plugin ist der einzige Teil von nbshell, der von sich aus ins Netz
geht.** Es fragt [open-meteo.com](https://open-meteo.com) — ohne Schluessel,
ohne Konto. Was den Rechner verlaesst: einmal der Ortsname (Umrechnung in
Koordinaten, das Ergebnis bleibt im Zwischenspeicher liegen), danach alle
15 Minuten die Koordinaten. Nichts fragt das Geraet nach seinem Standort, und
ohne `curl` bleibt die Zelle einfach still. Der Zwischenspeicher liegt in
`~/.cache/nbshell` und wird auch benutzt, wenn gerade kein Netz da ist — dann
steht eben ein aelterer Stand da, statt dass die Zelle leer wird.

`install.sh` legt beide an, wenn sie fehlen. Sie wird
**nie ueberschrieben**: was in `plugins/` liegt, gehoert dir und ueberlebt jede
Aktualisierung. Genau das war der Grund fuer den Umbau — vorher stand jeder
Baustein in einer `switch`-Anweisung in `WidgetHost.qml` und noch einmal als
Name im Anordnen-Menue, und beim naechsten `install.sh` war die eigene
Aenderung weg.

Im Plugin steht zur Verfuegung, was die Shell selbst benutzt:

| | |
|---|---|
| `qs.Common` | `Config`, `Theme`, `Icons`, `Runtime` |
| `qs.Widgets` | `Cell`, `Popout`, `IconText`, `Glyph`, `LevelBar`, `MenuView` |
| `qs.Services` | `Niri`, `Audio`, `Net`, `Bt`, `Notify`, `MediaService`, `Calendar`, … |

Die Wurzel ist ein `Cell` — die Leiste liest davon `shown`, `implicitWidth` und
`implicitHeight`. **Ausblenden ueber `shown`, nicht ueber `visible`**: die
Sichtbarkeit eines Kindes enthaelt immer die des Elternteils, und die Huelle
wuerde ihre eigene Antwort lesen.

Drei Dinge, die dabei zaehlen:

- **Geladen wird nur, was eingeplant ist.** Ein Plugin, das in keiner der vier
  Bausteinlisten steht, entsteht gar nicht erst und kostet nichts.
- **Ein kaputtes Manifest darf die Leiste nicht leeren.** `scripts/plugins.sh`
  ueberspringt es mit einer Meldung im Journal; der Rest laedt normal.
- **Eine Kennung wie ein eingebauter Baustein wird abgelehnt**, statt ihn zu
  ersetzen — sonst kaeme es darauf an, wer zuerst gelesen wurde.

## Wie es gebaut ist

```
shell/
  shell.qml            Einstiegspunkt, IPC
  Common/Config.qml    config.json, beobachtet
  Common/Theme.qml     Palette + Zeichenraster
  Common/Runtime.qml   fluechtiger Zustand, den alle Fenster teilen
  Services/Niri.qml    niri-IPC: Arbeitsflaechen, Fenster, Tastatur
  Services/SysInfo.qml /proc/stat und /proc/meminfo
  Services/Audio.qml   Pipewire: Lautstaerke, Geraete
  Services/Apps.qml    .desktop-Eintraege, Suche, Starten
  Services/Net.qml     NetworkManager ueber Quickshell
  Services/Bt.qml      BlueZ ueber Quickshell
  Services/Brightness.qml  sysfs lesen, logind setzen
  Services/Osd.qml     Zustand der Einblendung
  Services/Notify.qml  Benachrichtigungsserver, Archiv
  Services/Session.qml Sperren, Abmelden, Ausschalten
  Services/Clipboard.qml  Verlauf ueber wl-paste --watch
  Services/MediaService.qml  MPRIS
  Widgets/LevelBar.qml Balken aus Bloecken
  Widgets/MenuView.qml DBus-Menues als Liste
  Widgets/Cell.qml     der eine Baustein, aus dem alles besteht
  Bar/Bar.qml          das Fenster: Insel oder Balken
  Bar/Wallpaper.qml    Hintergrundbild je Bildschirm
  Launcher/Launcher.qml  Anwendungsstarter
niri/nbshell-takeover.kdl  Binds fuer den Umstieg
  Osd/Osd.qml          die Einblendung je Bildschirm
  Notifications/Popups.qml  die Karten am Rand
  Power/PowerMenu.qml  Sitzungsmenue
  Procs/ProcessList.qml  Prozessliste
  Settings/SettingsMenu.qml  Optionsmenue
  Services/Procs.qml   ps lesen, Prozesse beenden
  Services/CaptureService.qml  Screenshots, Aufnahme, OCR
  Services/ThemeExport.qml  Palette nach ghostty und ins eigene Skript
  Services/AiUsage.qml  Verbrauch der KI-Zugaenge
  Capture/CaptureMenu.qml   das Aufnahme-Menue
  scripts/capture.sh   die Shell-Arbeit danach
  Bar/WidgetHost.qml   Name -> Komponente
  Bar/Widgets/         die Bausteine
  Widgets/Popout.qml   Fenster, das an einer Zelle haengt
  Services/ThemeIndex.qml  Themeliste, Wechsel, Blaettern
  scripts/themes.sh    findet Themes und Wallpaper
```

**Insel, Pille und Balken sind dasselbe Fenster.** Es ist immer
bildschirmbreit und durchsichtig; nur der Rahmen darin waechst, und eine
`Region`-Maske haelt die durchsichtige Flaeche klickdurchlaessig. Der
Unterschied ist fast nur Geometrie — plus die `exclusiveZone`: als Balken
reserviert die Leiste ihren Platz und schiebt die Fenster weg, als Insel und
als Pille schwebt sie darueber. Die Pille kostet dabei genau eine Zeile:
`expanded` ist in ihr immer wahr.

**Die drei Gruppen gibt es nur einmal.** Sie sitzen in einer Reihe, deren zwei
Zwischenraeume ihre Breite wechseln: im Balken so gerechnet, dass die Mitte
wirklich mittig steht, in der Insel auf einen Zeichenabstand. So muss nichts
doppelt gebaut werden, und der Uebergang laesst sich animieren.

## Fallstricke

- **Eine `MouseArea` mit `hoverEnabled` nimmt das Ueberfahren fuer sich.** Ein
  `HoverHandler` weiter oben — etwa der des Popoutfensters — sieht es dann
  nicht mehr, haelt die Maus fuer verschwunden und startet den Nachlauf: nach
  2,5 s klappt das Popout zu, mitten im Lesen. Im Kalender faellt das auf, weil
  man dort laenger auf einer Zelle verweilt. In Popouts gehoeren deshalb
  `HoverHandler` und `TapHandler` hin; Handler blockieren einander nicht.
- **Quickshells IPC-Aufrufer liest eckige Klammern als Argumentliste** und
  zerlegt ausserdem an Kommas und Semikola: `qs ipc call config set k '["a"]'`
  kommt als zwei Argumente an. Steuerzeichen helfen nicht, 0x1F ist sein
  eigenes Trennzeichen — `bin/nbshell` schickt `[ ] , ; %` deshalb
  prozentkodiert, `shell.qml` dreht es zurueck.
- **Ein Baustein blendet sich ueber `shown` aus, nie ueber `visible`.** Die
  Sichtbarkeit eines Kindes enthaelt immer die des Elternteils — fragt die
  Huelle `item.visible` ab, um ihr eigenes `visible` zu setzen, liest sie ihre
  eigene Antwort, und beide bleiben fuer immer unsichtbar. Lautlos.
- **Kinder eines Positionierers duerfen keine `anchors` haben.** Mit ihnen
  meldet die Reihe Breite 0, der Kasten darum schrumpft auf nichts, und man
  sucht den Fehler beim Fenster — obwohl das laengst da ist (`niri msg
  -j layers` zeigt es). Genau so ist die Einblendung anfangs unsichtbar
  geblieben.
- **niri beantwortet pro Verbindung genau EINE Anfrage** und legt dann auf.
  Ein dauerhaft offener Befehls-Socket funktioniert damit einmal und schweigt
  danach — lautlos, weil das Schreiben selbst gelingt. Befehle gehen deshalb
  ueber `niri msg action`; der Socket bleibt fuers Zuhoeren.
- **Was ein `Repeater` als `modelData` herausgibt, ist eine eigene Verpackung
  desselben Werts.** Ein `!==` gegen den Eintrag in der Quellliste trifft
  deshalb IMMER zu — die Benachrichtigungskarten blieben so ewig stehen,
  obwohl der Timer ablief und die Funktion lief. Gesucht wird ueber eine id.
- **`selection` ist kein Hover-Hintergrund.** Es ist die Farbe fuer markierten
  Text und in manchen Themes fast weiss — als Flaeche unter der Maus blendet
  sie, und jede Schrift darauf muss umgerechnet werden. `Theme.hover` wird
  stattdessen aus dem Hintergrund gemischt: immer dezent, und der normale Text
  bleibt ohne Rechnerei lesbar.
- **Eine Zeile, die ihre Breite vom Positionierer holt (`width: column.width`),
  kann dazu fuehren, dass der `Repeater` sie gar nicht erst erzeugt** — ohne
  Fehler, ohne Meldung. Im Baustein-Editor blieben beide Listen leer, obwohl
  die Modelle nachweislich gefuellt waren; mit festen Breiten am Fenster
  standen sie sofort da.
- **`export` ist in JavaScript ein Schluesselwort.** Eine IPC-Funktion so zu
  nennen laesst die ganze Datei nicht mehr laden — die Shell startet dann gar
  nicht mehr.
- **Ein `signal` auf einem Singleton kam bei den Zellen nicht an**, eine
  Aenderungsmeldung dagegen zuverlaessig — deshalb schliesst ein hochgezaehlter
  `closeToken` die Popouts und kein Signal.
- **`qs ipc call <ziel> show` ruft nicht die Funktion `show`**, sondern die
  CLI versteht ihr eigenes `ipc show` und listet die Ziele auf. IPC-Funktionen
  also nicht `show` nennen.
- **Eine Bindung darf nicht setzen, was sie liest.** `player` las `lastActive`
  und `onPlayerChanged` schrieb es wieder — „Binding loop detected", und der
  Wert zappelt. Gemerkt wird jetzt nur noch, wer *spielt*.
- **Ein Positionierer rechnet seine implizite Groesse selbst aus.** `Column`
  und `Row` verweigern jede Zuweisung an `implicitWidth`/`implicitHeight`
  („read-only property") — die Breite gehoert an die Kinder.
- **Ein `Loader` darf keine eigene Groesse bekommen**, sonst skaliert er sein
  Kind darauf; setzt das Kind seine Breite selbst, fallen beide auf 0.
- **Vorgabewerte koennen Fehler verstecken.** Der TOML-Leser hat anfangs nur
  eine einzige Zeile erwischt (die Raute jeder Farbe galt als Kommentar) — und
  weil die Vorgaben ein vollstaendiges Theme sind, sah alles richtig aus. Faellt
  die Palette zu klein aus, warnt die Shell jetzt.
- **Ein Singleton entsteht erst, wenn es jemand anfasst.** Ein Dienst, der von
  sich aus beobachten soll (Helligkeit, Netz, Audio), tut bis dahin gar nichts
  — und meldet beim ersten Zugriff brav Nullwerte, ohne dass etwas kaputt
  aussieht. `shell.qml` beruehrt sie deshalb einmal beim Start.
- **niri startet `spawn`-Befehle mit dem PATH des systemd-User-Managers**, und
  darin fehlt `~/.local/bin`. Ein `spawn "nbshell"` laeuft dort still ins
  Leere — die Binds rufen deshalb `sh -c "$HOME/.local/bin/nbshell …"` auf.
  Fuer die Zukunft legt `environment.d/10-local-bin.conf` den Pfad dazu.
- **`install.sh` beendet eine laufende Instanz.** Quickshell laedt bei jeder
  Dateiaenderung neu und wuerde mitten im Austausch eine halbe Shell lesen.

## Verhaeltnis zu DMS

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bleibt
installiert und ist die Rueckfallebene, solange hier noch etwas fehlt. Beide
koennen gleichzeitig laufen — nbshell beansprucht bewusst keine D-Bus-Namen
(Benachrichtigungen, Tray). Sobald das noetig wird, muss eine von beiden weichen.

## Was noch fehlt

Der Reihe nach, wie es fuer den Alltag zaehlt:

- **Netz ohne NetworkManager** — nur dessen Backend ist angebunden.
- **Bilder in der Zwischenablage** — der Verlauf kennt nur Text.
- **Anwendungslautstaerken** — die Stroeme einzelner Programme.
- **Sperrbildschirm** — hier wird bewusst nichts Eigenes gebaut; ein Fehler
  darin sperrt dich aus. hyprlock tut es.

## Lizenz

MIT, siehe `LICENSE`.
