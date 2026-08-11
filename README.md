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

1. **Pakete** -- die 36, die nbshell braucht
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
| **der Abgleich der Aufgaben** | Syncthing wird zwar installiert, aber Geraete koppeln sich nur ueber die Oberflaeche auf `127.0.0.1:8384` -- ein Skript kann das nicht. Danach `nbshell set todoFile '~/Sync/nbshell/todo.json'` auf **beiden** Rechnern, sonst fuehrt jeder seine eigene Liste. Siehe „Aufgaben". |

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
| `hyprpolkitagent` | das Fenster, das nach dem Passwort fragt (siehe „Rechteabfragen") |
| `qrencode` | WLAN als QR-Code im Control Center |
| `speedtest-cli` | Durchsatz messen, ebenda |
| `headsetcontrol` | Akkustand im Headset-Plugin |
| `syncthing` | Aufgabenliste mit dem Telefon abgleichen |

**Zwei Dinge kommen NICHT mit** und bleiben auf einem frischen Rechner leer:

- **Wallpaper.** Die 21 Themes enthalten nur ihre `colors.toml` (84 KB statt
  91 MB). Die Bilder holt `omarchy2dms --fetch-wallpapers` einmalig in einen
  Zwischenspeicher, den nbshell mitbenutzt -- oder ein per
  `nbshell theme install` geholtes Theme bringt sein `backgrounds/` selbst mit.
- **Der KI-Verbrauch.** Der Baustein `ai` braucht `get-provider-usage` aus dem
  DMS-Plugin `aiOverviewControl`. Fehlt es, bleibt die Zelle still (`aiHelper`
  in der Config zeigt auf einen eigenen Pfad).

**Mehrere Anbieter gleichzeitig** -- das Skript kennt ueber dreissig, gefragt
wird, was in `aiProviders` steht. Je Anbieter eine Zeile mit Balken, darunter
die weiteren Toepfe.

Die Anbieter zaehlen dabei verschieden: Claude hat **Zeitfenster** ("5 hour",
"7 day") und beschreibt sie in `resetDescription`, Antigravity hat
**Modellgruppen** ("Gemini Models", "Claude & OpenAI Models") und legt den
Namen in `name`. Beides ist die Beschriftung des Balkens, deshalb gilt `name`
zuerst und `resetDescription` danach -- sonst stuende bei Antigravity dreimal
derselbe Text und man wuesste nicht, welcher Balken wofuer ist. Und weil
Antigravity einen dritten Topf hat, ist die Liste offen statt auf zwei
festgelegt.

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

nbshell launcher         # Starter: Anwendungen UND Befehle (Alias: run)
nbshell palette          # derselbe Starter, nur die Befehle
nbshell find ghost       # zeigt, was er finden wuerde
nbshell befehle [text]   # alle Befehle der Palette
nbshell befehl "Ton aus" # den besten Treffer ausfuehren

nbshell text             # Schriftgroessen von Shell, GTK und Terminal
nbshell text 15          # alle drei zusammen umstellen

nbshell polkit           # laeuft ein Agent fuer Rechteabfragen?
nbshell polkit on

nbshell plugin add <url> # fremdes Bar-Widget aus git holen
nbshell plugin update
nbshell plugin remove <name>

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

nbshell todo             # Aufgaben auflisten
nbshell todo Muell rausbringen   # eintragen (auch: todo add <text>)
nbshell todo toggle      # die Liste als Fenster (Mod+T)
nbshell todo done 2      # abhaken, Nummer aus `nbshell todo`
nbshell todo drop 2      # wegwerfen
nbshell todo clear       # alle erledigten aufraeumen
nbshell todo sync        # Konfliktkopien einsammeln und neu lesen
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
Mod+Shift+D hotkey-overlay-title="nbshell: Befehlspalette" {
    spawn "nbshell" "palette";
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
`collapseDelay`, `clockFormat`, `clockFormats`,
`clipboardGuardSecrets`, `notifyReviveMs`, `appScopes`, `terminalRatio`,
`accent` (Rolle), `widgets` (Aussehen je Baustein), `updateNoconfirm`,
`idle`, `caffeine`, `idleSaver`, `idleDim`, `idleScreenOff`, `idleLock`, `idleDimPercent`,
`batteryWarnAt`, `deviceLowAt`, `deviceWarnAt`, `speedScale`,
`cursorTheme`, `cursorSize`, `nearby`,
`titleLength`, `locale`, `wallpaper`, `wallpaperOverride`, `maxVolume` und die
vier Bausteinlisten.

## Themes — omarchy2dms, hier eingebaut

Umrechnen muss nbshell nichts: es liest Omarchys `colors.toml` direkt, es gibt
kein Zielformat mehr. Von [omarchy2dms](https://github.com/nerdislb/omarchy2dms)
bleibt damit nur das Suchen und Auflisten uebrig, und das erledigt
`scripts/themes.sh` in einem Aufruf — Name, Modus, zwoelf Farben fuer die
Vorschau und das erste Wallpaper.

### Die Vorschau

Der Themewaehler (`nbshell picker`, oder ein Klick auf den Baustein `themes`)
zeigt oben eine **Miniatur der eigenen Leiste, in den Farben des Kandidaten
gezeichnet**, darunter dessen Palette als lueckenloser Streifen. Faehrt die
Maus durch die Liste, wechselt die Vorschau mit; verlaesst sie die Liste, steht
wieder das aktive Theme da. Die Kopfzeile sagt, was gerade gilt:
`THEME · AKTIV` oder `THEME · VORSCHAU`.

Omarchy 4 loest dasselbe mit einem Karussell aus **vorgerenderten
Desktop-Screenshots** — pro Theme ein Bild, das jemand aufnehmen und
mitliefern muss. Das geht hier nicht und soll es auch nicht: unsere Themes
bringen nur ihre `colors.toml` mit (84 KB statt 91 MB, siehe oben). Gezeichnet
statt geladen heisst: nichts im Zwischenspeicher, nichts nachzuladen, und ein
frisch installiertes Theme hat seine Vorschau sofort.

Und sie zeigt das Richtige. Ein fremder Desktop beantwortet „wie sieht das
aus" mit einem Bild von jemand anderes Bildschirm; die Miniatur antwortet mit
der Leiste, die man gleich vor sich hat.

Zwei Kleinigkeiten stecken darin:

- **Was ein Theme nicht nennt, wird abgeleitet** — schon in `themes.sh`, nicht
  erst in QML. Ein leerer Farbwert ist in QML durchsichtig, und die Miniatur
  haette Loecher, durch die das AKTUELLE Theme durchscheint: die
  irrefuehrendste aller Vorschauen.
- **Kein Fenstertitel in der Miniatur.** Bei 34 Zeichen Breite stiess er in
  der Mitte auf die Uhr, und „nbshell12:34" ist keine Vorschau, sondern ein
  Fehler.

Wallpaper werden an drei Stellen gesucht: beim Theme selbst
(`<theme>/backgrounds/`), im Zwischenspeicher von omarchy2dms
(`~/.local/share/omarchy2dms/wallpapers/<theme>/`, den beide teilen) und unter
`~/.local/share/nbshell/wallpapers/<theme>/`.

### Der Akzent ist eine Rolle, keine Farbe

```bash
nbshell accent           # welche Rolle gilt, und wie jede im aktuellen Theme aussieht
nbshell accent yellow
nbshell accent theme     # zurueck zum Vorschlag des Themes
```

In der Config steht nicht `#e0af68`, sondern `yellow`. Aufgeloest wird das
gegen die Palette des **gerade aktiven** Themes: wer „das Gelbe" waehlt,
bekommt beim Wechsel von gruvbox auf nord nordens Gelb. Zur Wahl stehen
`theme` (Vorgabe), `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`,
`orange` und `foreground`.

Die Idee stammt aus [Shibumi-Shell](https://github.com/HANCORE-linux/Shibumi-Shell)
(HANCORE, MIT), wo der Akzent als `color01`…`color08` gespeichert wird. Der
Gewinn ist nicht die Auswahl, sondern **was nicht passiert**: ein fester
Farbwert waere nach dem naechsten Themewechsel ein Fremdkoerper — im besten
Fall unpassend, im schlechtesten auf dem neuen Hintergrund nicht mehr zu
lesen. Eine Rolle kann das nicht, weil jede Wahl aus einer Palette kommt, die
der Themeautor abgestimmt hat.

Der gewaehlte Akzent gilt **auch ausserhalb der Leiste**: `NB_ACCENT` in der
Palettendatei, der Cursor in ghostty und die Fensterrahmen in niri. Wer die
Leiste auf Gruen stellt, will keinen blauen Rahmen daneben.

Im Themewaehler steht die Reihe als Farbkaestchen unter der Vorschau — das
aktive mit hellem Ring, `theme` mit einem Punkt, weil es keine eigene Farbe
ist, sondern ein Verweis.

### Aussehen je Baustein

Form, Symbol und Farbe gelten fuer alle gemeinsam — ausser fuer die Bausteine
mit eigenem Eintrag:

```bash
nbshell widget                     # wer ein eigenes Aussehen hat
nbshell widget battery display icon    # nur das Symbol (full | icon | text | auto)
nbshell widget clock style plain       # ohne Kasten (box | bracket | plain | auto)
nbshell widget updates color red       # eine Farbe DES THEMES (auto = wie alle)
nbshell widget updates reset
nbshell widget reset all
```

In der Config:

```json
"widgets": {
  "battery": { "display": "icon" },
  "updates": { "color": "red" }
}
```

Nachgebaut nach Shibumis Appearance-Seite, die dieselben drei Regler je
Baustein hat (DISPLAY / SURFACE / COLOR). Was nicht eingetragen ist — oder auf
`auto` steht —, kommt weiter aus der allgemeinen Einstellung: wer nichts setzt,
merkt von der ganzen Sache nichts, und die Config bleibt kurz.

Zwei Feinheiten:

- **Die Farbe ersetzt nur die neutrale.** Ein roter Akku und eine rote
  Prozessorlast sind Warnungen, keine Gestaltung — sie einzufaerben hiesse,
  die einzige Aussage zu loeschen, die die Zelle in dem Moment hat. Die
  gedaempfte Fassung (`Theme.textDim`) bleibt gedaempft.
- **`display` wirkt nicht auf Bausteine mit eigenem Inhalt** (`custom: true`:
  Arbeitsflaechen, Systemlast, Medien). Die bauen ihre Zeile selbst und fragen
  `widgetIcons` direkt; ihnen ein Symbol wegzunehmen hiesse, sie umzuschreiben.

Nachschlagen kann das jede Zelle selbst, weil sie ihre `widgetId` ohnehin
kennt — die Leiste haengt sie fuer die Popout-Steuerung an.

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

## Anwendungsstarter und Befehlspalette

`Mod+Space` (mit dem Takeover, sonst frei belegbar) oder `nbshell launcher`.
Tippen sucht, `↑↓` (oder `Ctrl-N`/`Ctrl-P`)
waehlt, Enter startet, Esc schliesst. Findet die Eingabe nichts, wird sie als
Befehl ausgefuehrt — wie in einem Terminal, nur ohne eines zu oeffnen.

Gesucht wird in **beidem**: in den installierten Anwendungen und in allem, was
nbshell selbst kann. „gruv" und Enter wechselt das Theme, „aufgab" oeffnet die
Liste, „stumm" schaltet den Ton ab. Der Gedanke stammt aus Omarchy 4: dort sind
Starter und Systemmenue zu einer Flaeche verschmolzen, weil zwei Paletten mit
zwei Tastenkuerzeln nichts trennen, was zusammengehoert. Vorher musste man
wissen, dass das Theme hinter `Mod+Comma` steckt und die Aufgaben hinter
`Mod+T`.

| Eingabe | sucht in |
|---|---|
| `firefox` | Anwendungen **und** Befehlen, nach Punkten gemischt |
| `>theme` | nur Befehlen (`Mod+Shift+Space` oeffnet gleich so) |
| `!term` | nur Anwendungen |

Befehle erkennt man an drei Dingen: dem `>` im Kasten statt eines Symbols, der
Kategorie am rechten Rand (`FENSTER`, `THEME`, `SITZUNG`, …) und daran, dass
bei gleichem Treffer die Anwendung vorn steht — der Starter war zuerst fuer sie
da (`commandBias`, 0.9).

Was sich nicht zurueckdrehen laesst — Ausschalten, Neu starten, Abmelden,
Ruhezustand — **fragt nach**: das erste Enter markiert, die Fusszeile wird rot,
das zweite fuehrt aus, Esc nimmt zurueck. In einer Suchpalette liegt der
Feierabend sonst einen Tippfehler entfernt.

Auf der Befehlszeile:

```
nbshell befehle           alle Eintraege mit Kategorie
nbshell befehle theme     danach gefiltert
nbshell find gruv         was der Starter zu "gruv" anbietet, gemischt
nbshell befehl "Ton aus"  den besten Treffer ausfuehren
nbshell palette           Starter gleich als Befehlspalette oeffnen
```

`nbshell befehl` fuehrt **nicht** aus, was nachfragt: ein Skript, das sich
vertippt, soll den Rechner nicht herunterfahren. Solche Befehle gehen nur im
Fenster.

Eigene Eintraege kommen aus `~/.config/nbshell/commands.json` — eine Liste, die
beim Speichern sofort greift:

```json
[
  { "name": "Notizen", "comment": "Obsidian-Tresor", "run": "obsidian" },
  { "name": "VPN an", "category": "Netz", "run": "nmcli con up buero" }
]
```

Eingebaute Befehle rufen die Shell direkt an; nur eigene starten einen Prozess.
Der Unterschied ist Absicht: fuer ein `Runtime.todoOpen = true` ein Programm zu
starten, das der Shell per IPC zurueckruft, waere dreimal um den Block.

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

**Jede Anwendung bekommt ihren eigenen systemd-Scope**
(`app-nbshell-<name>-<zahl>.scope` in `app.slice`). Ohne das haengt alles
Gestartete an nbshell und damit im selben Cgroup wie die Shell: laeuft ein
Programm mit dem Speicher davon, sucht sich `systemd-oomd` das groesste Cgroup
— und das ist dann die Sitzung, nicht der Uebeltaeter. Uebernommen aus
Omarchy 4.

`--scope` und nicht `--user <dienst>`: der Scope wird von `systemd-run` selbst
abgezweigt und erbt die Umgebung der Shell samt Wayland-Socket; ein Dienst
bekaeme die des User-Managers und faende keinen Bildschirm. Fehlt `systemd-run`,
wird direkt gestartet — geprueft wird das einmal beim Start, denn ein fehlendes
Werkzeug darf nicht heissen, dass gar nichts mehr aufgeht. Abschalten:
`appScopes: false`.

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

**Der Stapel laesst der Leiste ihren Platz.** Steht er auf derselben Seite
(`notifyCorner: top` bei einer Leiste oben), faengt er unter ihr an. Von allein
tut er das nicht: das Fenster liegt auf der Overlay-Ebene und ignoriert die
reservierte Zone — was richtig ist, sonst schoebe jede Karte die Fenster
darunter beiseite. Es nimmt sich den Platz deshalb selbst, in der Insel und in
der Pille samt Abstand zum Rand.

Der Baustein `notifications` zeigt die Anzahl, sein Popout das Archiv mit
„nicht stoeren" und „leeren". Rechtsklick auf die Zelle schaltet direkt stumm.

### Das Archiv ueberlebt den Neustart

Es liegt in `~/.local/state/nbshell/notifications.json`. Der Grund ist
handfest: **jedes `install.sh` und jedes `nbshell restart` startet die Shell
neu.** Lag die Liste nur im Speicher, war eine ungelesene Meldung danach weg —
ausgerechnet beim Aktualisieren, wo am ehesten etwas schiefgeht. Karten, die
beim Beenden noch am Rand standen, kommen sogar zurueck auf den Bildschirm,
sofern sie juenger sind als `notifyReviveMs` (5 min); ohne diese Grenze staende
nach einer Nacht im Standby der ganze Stapel von gestern wieder da. Dieselbe
Ueberlegung wie in Omarchy 4 („popups survive shell restarts").

Ein Eintrag ist die **Kopie**, nicht die Benachrichtigung: Programmname, Titel,
Text, Dringlichkeit, Zeitpunkt. Das lebende Objekt haengt daneben und nur
solange es das gibt — es liefert die Aktionsknoepfe und das `dismiss`. Was aus
der Datei kommt, hat keines; deshalb zeigt eine wiederhergestellte Karte keine
Knoepfe mehr.

Gesucht wird ueber `key` (Zeitstempel + id), **nicht** ueber `id`: der Server
faengt nach einem Neustart wieder bei 1 an, eine frische Meldung haette sonst
dieselbe id wie eine aus der Datei — und ein Klick raeumte beide weg.

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
| `Mod+Space` | spotlight | Starter: Anwendungen **und** Befehle |
| `Mod+Shift+Space` | — | dieselbe Flaeche, nur die Befehle |
| `Mod+N` | notification center | Benachrichtigungsarchiv |
| `Mod+V` | clipboard | Zwischenablage |
| `Super+X` | powermenu | Sitzungsmenue |
| `Mod+M`, `Ctrl+Alt+Entf` | processlist | Prozessliste |
| `Mod+Comma` | settings | Optionsmenue |
| `Mod+Y` | Wallpaper-Browser | Hintergrund-Karussell |
| `Mod+Alt+L` | lock | `lockCommand` (Vorgabe hyprlock) |
| `XF86MonBrightnessUp/Down` | brightness | nbshells Helligkeitsdienst |
| `XF86AudioPlay/Next/Prev` | mpris | MPRIS-Anbindung |
| `Mod+T` | — | Aufgabenliste (kein DMS-Erbe, war frei) |

**Was tot bleibt**, weil nbshell es nicht hat: `Mod+Shift+N` (Notizblock),
`Mod+Shift+W` (Fensterregeln), `Ctrl+Shift+R` (Arbeitsflaeche umbenennen) und
`Ctrl`+Lautstaerke (Lautstaerke des Players statt der Anlage). Alle vier stehen
in `dms/binds.kdl` und zeigen auf ein abgeschaltetes DMS -- sie tun nichts,
kosten aber auch nichts.

**Die Helligkeitstasten waren monatelang genau so tot** und niemandem
aufgefallen: eine Taste, die nichts tut, meldet sich ja nicht. Gefunden hat sie
erst das Durchzaehlen der DMS-Altlasten.

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

### QR-Code und Durchsatz

Zwei Knoepfe in der WLAN-Zeile des Control Centers, beide aus dem
Plugin-Katalog uebernommen. Beide oeffnen ein **Fenster**, kein Popout -- ein
Popout klappt zu, sobald die Maus es verlaesst, und genau das tut man, wenn
man zum Telefon greift oder eine halbe Minute auf eine Messung wartet. Auch
per `nbshell qr` und `nbshell speed`.

**Der QR-Code.** Erster Versuch: der Code als Halbblockzeichen in den Farben
des Themes, mitten ins Popout. Das sah zur Shell passend aus und **liess sich
nicht scannen** -- gleich dreifach falsch:

1. hell auf dunkel ist die Umkehrung dessen, was ein QR-Code sein soll, und
   viele Kameras lesen sie nicht;
2. die Ruhezone war ein Modul breit statt der vorgeschriebenen vier;
3. der gestauchte Zeilenabstand (0.85) verzerrte die Module.

Jetzt liefert `wifi-qr.sh` die **Modulmatrix** als JSON, und das Fenster malt
sie als schwarze Quadrate auf eine weisse Karte, gut 400 px breit. Das ist die
eine Stelle in nbshell, an der das Theme nichts zu sagen hat: ein Code, den
niemand scannen kann, ist kein Code.

Nachgeprueft wurde das nicht mit dem Auge, sondern gerechnet -- die Matrix
wurde als Bild nachgebaut und Pixel fuer Pixel mit dem PNG verglichen, das
`qrencode` selbst aus derselben Nutzlast macht: **0 Abweichungen**. Dabei fiel
auch auf, dass `printf '…;;\n'` den Zeilenumbruch in die NUTZLAST schreibt und
mitkodiert wird; er ist raus.

Das Passwort holt `nmcli -s`. Gehoert die Verbindung dem System und nicht dir,
fragt dabei polkit nach -- dafuer gibt es den Agenten. Kommt keines zurueck,
wird der Code trotzdem gebaut, und die Zeile darunter sagt, woran es lag.

**Der Durchsatz.** Balken statt Zahlenzeile, dieselben Bloecke wie ueberall.
Die Skala ist nicht fest, sondern waechst mit dem schnellsten je gemessenen
Wert (`speedScale`) -- 50 Mbit/s sind im Hotel viel und zu Hause wenig -- und
bleibt danach stehen, damit man vergleichen kann.

`speedtest-cli` liefert seine drei Werte alle auf einmal am Ende; es gibt also
nichts, was live steigen koennte. Statt einen Fortschritt zu erfinden, laeuft
waehrenddessen ein Lauflicht durch die Balken: man sieht, dass es arbeitet, und
wird nicht ueber den Stand belogen.

Der **Ping bekommt keinen Balken** -- bei ihm ist klein gut, und ein Balken,
der bei "gut" fast leer ist, liest sich falsch herum. Unplausible Werte werden
verschwiegen statt gezeigt: `speedtest-cli` meldet gegen manche Gegenstellen
1.800.000 ms, und eine offensichtlich falsche Zahl ist schlechter als keine.

Bevorzugt wird `speedtest-cli` aus `extra` und nicht Ooklas eigenes aus dem
AUR: letzteres will beim ersten Start eine Lizenz bestaetigt haben.

## Mauszeiger

```bash
nbshell cursor            # Thema, Groesse, und was installiert ist
nbshell cursor Adwaita 28
```

Geschrieben wird `~/.config/niri/nbshell-cursor.kdl` und einmalig eine
include-Zeile in die `config.kdl` -- mit Sicherung daneben und `niri validate`
davor, wie bei allen anderen Eingriffen in die niri-Config. niri exportiert
Thema und Groesse an alles, was es startet (`XCURSOR_THEME`, `XCURSOR_SIZE`);
laufende Programme behalten ihren Zeiger.

**GTK zieht mit.** Dateidialoge, nautilus und alles andere auf GTK-Basis
fragen nicht niri, sondern gsettings -- ohne diesen Teil haette man einen
halben Wechsel, der genau dort auffaellt, wo man ihn am wenigsten erwartet.

Beides steht auch im Optionsmenue unter AUSSEHEN (**Mauszeiger** und
**Zeigergroesse**) -- die Werte kommen dort aus dem Dateisystem, nicht aus einer
gepflegten Liste: welche Themen es gibt, weiss nur, wer nachsieht. Ein leerer
erster Eintrag heisst „nbshell laesst die Finger davon"; auf einem Rechner, auf
dem jemand seinen Zeiger schon anders eingerichtet hat, soll die blosse
Anwesenheit der Shell nichts umstellen.

Die Wahrheit steht dabei in der **Config** (`cursorTheme`, `cursorSize`), nicht
in der niri-Datei: `Services/Cursor.qml` zieht beide anderen Stellen nach,
sobald sich einer der Werte aendert. Wer direkt in die kdl schriebe, haette
zwei Wahrheiten, und die naechste Aenderung im Menue ueberschriebe sie wortlos.
Beim Blaettern im Menue wartet der Dienst 250 ms ab -- sonst schriebe jeder
Tastendruck eine Datei, riefe zweimal gsettings, und niri laedt bei jeder
Aenderung seine Config neu.

### Ein Theme dazuholen

Ein Zeigerthema ist nur ein Verzeichnis mit Bilddateien, kein Programm. Es
gehoert nach `~/.local/share/icons/<Name>/` und steht danach sofort zur Wahl --
nichts wird installiert, nichts gestartet, kein sudo.

So kamen die macOS-Zeiger hierher (`apple_cursor`, GPL-3.0):

```bash
curl -LO https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.xz
tar -tJf macOS.tar.xz | head            # erst hineinsehen
tar -xJf macOS.tar.xz -C ~/.local/share/icons --strip-components=1
nbshell cursor macOS 24
```

Das Archiv enthaelt ausser `.theme`-Dateien nur Zeigerbilder und relative
Verweise (`arrow -> left_ptr`) -- keine Skripte, keine absoluten Pfade. Das ist
der Grund, warum man es guten Gewissens von Hand auspacken kann, statt ein
AUR-Paket bauen zu lassen, das dafuer ein PKGBUILD ausfuehren wuerde.

`nbshell cursor` ohne Argumente meldet nebenbei ein Erbstueck, falls es da ist:
`dms/cursor.kdl` wird von der niri-Config eingebunden, ist aber **0 Bytes
gross**. Es tut nichts -- aber zwei Stellen fuer dieselbe Sache sind eine zu
viel, und wer aufraeumen will, weiss jetzt davon.

## Rechteabfragen (polkit)

```bash
nbshell polkit        # laeuft einer?
nbshell polkit on     # einen vorhandenen einschalten
```

**`polkitd` fragt niemanden.** Es erwartet einen Agenten *in* der Sitzung, der
das Fenster mit der Passwortabfrage aufmacht. Unter einem Desktop bringt die
Umgebung ihn mit; unter niri bringt ihn niemand mit — und man merkt es erst,
wenn ein Programm nach Rechten fragt und scheinbar nichts passiert. Kein
Fehler, keine Meldung, nur „nicht berechtigt".

nbshell hat **keinen eigenen**: Quickshell hat keine Anbindung an polkit.
Stattdessen wird ein vorhandener eingeschaltet, in dieser Reihenfolge:
`hyprpolkitagent` (Qt/QML wie die Shell selbst, in `extra`, laeuft unter jedem
wlroots-Kompositor), `polkit-gnome`, `lxqt-policykit`, `mate-polkit`.

`nbshell switch on` schaltet ihn mit ein, `nbshell switch status` zeigt ihn an.
`switch off` laesst ihn **an**: der Agent gehoert nicht DMS, und DMS bringt
selbst keinen mit — ihn wieder abzuschalten hiesse, das Loch zurueckzugeben.

## Schriftgroesse in einem Zug

```bash
nbshell text          # was gerade gilt
nbshell text 15       # Shell, GTK und Terminal zusammen
```

Nach Omarchys `omarchy display text size`. Vorher stellte man die Leiste um,
fand die Menues zu klein, stellte GTK nach — und das Terminal blieb, wie es
war. Drei Vorsichtsmassnahmen stecken darin:

1. **Das Terminal wird nicht auf die Pixelgroesse der Shell gesetzt.** Es
   rechnet in Punkt: hier stand ghostty auf 12 pt, waehrend die Leiste auf
   13 px steht. Die stumpfe Umrechnung (13 px = 9,75 pt) haette es beim ersten
   Aufruf um ein Viertel geschrumpft. Stattdessen wird das Verhaeltnis beim
   ersten Mal gemessen und als `terminalRatio` abgelegt.
2. **GTKs Skalierung rastet auf eine ganze Punktgroesse ein.** Krumme Werte
   schneiden in GTK Menueeintraege ab — derselbe Fehler, den Omarchy in dieser
   Runde behoben hat. Gerechnet wird gegen die echte GTK-Schrift
   (`gsettings get org.gnome.desktop.interface font-name`).
3. **Geschrieben wird nur, was es schon gibt.** Keine ghostty-Config, kein
   Eingriff; kein `gsettings`, kein GTK-Teil. Von der ghostty-Config liegt
   vorher eine Sicherung als `config.vor-nbshell` daneben, und ghostty
   bekommt danach `SIGUSR2` — von selbst liest es nicht neu.

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

**Bei der Videoaufnahme heisst ein Klick ohne Ziehen „alles".** Dort waehlt
`slurp` den Bereich, und ein versehentlicher Klick gab bisher eine Geometrie
von wenigen Pixeln zurueck — wf-recorder haette brav ein 3×2-Video begonnen.
Alles unter 8 px Kantenlaenge gilt jetzt als Ansage fuer den ganzen
Bildschirm, dieselbe Handbewegung wie in Omarchys Regionswaehler.

## KI-Verbrauch

```bash
nbshell set aiProviders "claude,antigravity"   # mehrere, kommagetrennt
nbshell ai                                      # Stand auf der Befehlszeile
```

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

**Eine geschriebene Datei ist noch keine Farbe.** Die beiden Empfaenger
verhalten sich naemlich verschieden:

| | |
|---|---|
| niri | liest den Include von selbst neu, sobald er sich aendert — nichts zu tun |
| ghostty | liest seine Konfiguration **nicht** von selbst neu |

Ghostty hoert dafuer auf `SIGUSR2` („received SIGUSR2, reloading
configuration" steht so im Programm), und genau das schickt nbshell nach dem
Schreiben — sonst saehe man das neue Theme erst im naechsten Fenster. Das
Signal kommt **verzoegert**: die Datei wird atomar geschrieben (schreiben,
umbenennen), und kaeme das Signal davor an, laese Ghostty die alte Fassung.

Andere Terminals bringen ihr eigenes Nachladen mit — alacritty beobachtet
seine Datei.

### Der Rest des Systems: `theme-hook.sh`

Alles, was nicht ghostty oder niri ist, laeuft ueber ein eigenes Skript:
`~/.config/nbshell/theme-hook.sh`, aufgerufen mit Themename und Modus. Gibt es
die Datei nicht, passiert nichts.

**Die Farben muss es sich nicht zusammensuchen.** nbshell schreibt sie vorher
nach `~/.config/nbshell/palette.sh`, in einer Form, die eine Shell direkt
einliest:

```sh
. ~/.config/nbshell/palette.sh
echo "$NB_BG $NB_FG $NB_ACCENT $NB_MODE"
```

Darin sind **beide Dialekte** von Omarchys `colors.toml` schon aufgeloest
(benannte Schluessel und `color0`…`color15`) und alles Fehlende gemischt. Ein
Hook, der die `colors.toml` selbst liest, muesste das jedes Mal nachbauen —
und genau daran ist die Themevorschau schon einmal gescheitert.

Es gibt `NB_BG`, `NB_BG_DARK`, `NB_BG_LIGHT`, `NB_FG`, `NB_FG_DIM`,
`NB_FG_BRIGHT`, `NB_ACCENT`, `NB_MUTED`, `NB_SELECTION`, die 16 ANSI-Farben als
`NB_RED` … `NB_BRIGHT_WHITE`, dieselben als Liste in `NB_ANSI`, dazu
`NB_THEME` und `NB_MODE`.

**Ein fertiges Beispiel liegt in `examples/theme-hook.sh`:**

```bash
install -m 755 examples/theme-hook.sh ~/.config/nbshell/theme-hook.sh
```

Es deckt ab, was sich aus einer Palette wirklich erzeugen laesst:

| | |
|---|---|
| alacritty | volle Palette nach `nb-theme.toml`; alacritty beobachtet seine Dateien selbst |
| cava | `[color]` mit Farbverlauf von gedaempft zum Akzent, danach `SIGUSR1` |
| GTK | hell/dunkel ueber `gsettings … color-scheme` — daran haengen GTK4-Programme, die Portale und damit die Dateiauswahl in Browsern |
| bat | einmalig `--theme=ansi`: dann nimmt bat die Terminalfarben, und die faerbt nbshell ohnehin mit |

Fuer alacritty muss einmal die Importzeile stimmen — `nbshell switch on` biegt
sie um, so wie bei ghostty:

```toml
[general]
import = ["~/.config/alacritty/nb-theme.toml"]
```

**Was sich nicht mitfaerben laesst:** ein nvim-Colorscheme ist ein Plugin, keine
Palette. Die Widgetfarben eines GTK-Themes aus 16 Farben zu erzeugen ist ein
eigenes Projekt — deshalb nur hell/dunkel. Browser folgen derselben Vorliebe,
weiter kommt man ohne Erweiterung nicht.

Der Hook laeuft **verzoegert**, aus demselben Grund wie das Signal an ghostty:
`palette.sh` wird atomar geschrieben, und ein Hook, der zu frueh liest, faerbt
das halbe System auf das vorige Theme.

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

### Flatpaks zaehlen mit

Ist `flatpak` installiert, kommen dessen Updates in dieselbe Zahl und dieselbe
Liste. Gefragt wird `flatpak remote-ls --updates`; die installierte Version
steht in `flatpak list`, und erst beide zusammen ergeben das „von → nach".

**Zwei gleiche Versionen sind kein Fehler.** Ein Flatpak kann eine neue Fassung
bekommen, ohne die Versionsnummer zu aendern -- es ist ein anderer Commit.
`v1.6.0 → v1.6.0` saehe aus wie ein Bug, deshalb steht dort `v1.6.0 (neuer
Build)`.

Die Abfrage geht ins Netz und bekommt darum eine Zeitgrenze (`timeout`): ein
haengendes Flathub darf die Pruefung nicht blockieren.

### Aktualisieren ohne Rueckfrage

`[ aktualisieren ]` im Popout oder ein Rechtsklick auf die Zelle oeffnet ein
Terminal und laesst `scripts/updates.sh run` laufen: erst die Systempakete,
dann die Flatpaks. **Gefragt wird nur nach dem Passwort** -- `--noconfirm` und
`flatpak update -y`.

Was das mitbringt, gehoert dazugesagt: `--noconfirm` beantwortet auch die
Rueckfragen, die keine Ja/Nein-Frage sind. Ein Paket, das ein anderes ersetzt,
wird ersetzt; ein Konflikt wird zugunsten des neuen Pakets aufgeloest; bei
mehreren Anbietern gewinnt der erste; und paru legt keine PKGBUILDs mehr zur
Durchsicht vor. Wer das nicht will:

```bash
nbshell set updateNoconfirm false
```

Dann fragt wieder jeder Schritt nach, und `flatpak update` laeuft ohne `-y`.

Beide Teile laufen, auch wenn der erste etwas zu meckern hatte -- ein
gescheitertes AUR-Paket soll die Flatpaks nicht aufhalten. Der Rueckgabewert
bleibt trotzdem der schlechteste von beiden, und das Terminal bleibt bis zum
Tastendruck stehen: sonst sieht man nie, ob etwas schiefging.

Zwei Minuten nach dem Start prueft die Shell von selbst noch einmal nach. Wann
das Terminal fertig ist, weiss sie nicht -- aber eine Zahl in der Leiste, die
nach dem Update noch die alte ist, waere schlimmer als eine spaete.

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

## Leerlauf und Wachhalten

```bash
nbshell idle              # Stand der Automatik
nbshell wach              # Rechner wachhalten -- umschalten
nbshell idle off          # Automatik ganz abschalten
```

Bis vor kurzem passierte im Leerlauf **nichts**: der Bildschirm blieb an,
gesperrt wurde nie. Auf einem Geraet, das in eine Tasche wandert, war das die
groesste Luecke -- gefunden beim Durchsehen von
[omarchyplugins.com](https://omarchyplugins.com), wo es dafuer einen eigenen
Dienst gibt.

**Ohne Zusatzprogramm.** Quickshell spricht `ext-idle-notify` selbst
(`IdleMonitor`), und niri kann das Protokoll. `swayidle` oder `hypridle` waeren
ein zweiter Daemon mit einer zweiten Konfiguration, die man vergisst, sobald
man hier etwas aendert.

Drei Stufen mit eigenen Fristen:

| Stufe | Vorgabe | was passiert |
|---|---|---|
| `idleSaver` | 180 s | Bildschirmschoner |
| `idleDim` | 240 s | Bildschirm wird dunkler (`idleDimPercent`, 20 %) |
| `idleScreenOff` | 600 s | DPMS aus ueber `niri msg action power-off-monitors` |
| `idleLock` | 900 s | `lockCommand` -- derselbe wie im Sitzungsmenue |

`0` laesst eine Stufe ausfallen. Eingeschaltet wird der Bildschirm **nicht**
von uns: niri weckt ihn bei der naechsten Eingabe selbst. Die alte Helligkeit
wird gemerkt, nicht gerechnet -- sonst waere der Bildschirm nach jedem Zyklus
ein Stueck dunkler.

`respectInhibitors` ist an: ein Programm, das eine Sperre anfordert (jeder
Videoplayer tut das), haelt alle drei Stufen an. Ohne das ginge der Bildschirm
mitten im Film aus, und man lernt, die ganze Sache abzuschalten.

### Der Bildschirmschoner

Nach `idleSaver` (Vorgabe 180 s, also VOR dem Dimmen) geht ein Vollbildterminal
mit dem nbshell-Schriftzug auf. Von Hand: `nbshell saver`.

Nach Omarchys Vorbild -- dort laeuft `ttfx` mit einem zufaelligen Effekt auf
einer ASCII-Datei. `ttfx` gibt es nicht in den Repos, und ein Zeichenraster
ueber neun Zeilen zu bewegen braucht keine Bibliothek: `scripts/screensaver.py`
macht es selbst, mit **zehn** Effekten in zufaelliger Reihenfolge und einem
langsam wandernden Helligkeitsverlauf dazwischen:

| | |
|---|---|
| entschluesseln | die Zeichen zappeln und rasten nacheinander ein |
| regen | sie fallen von oben an ihren Platz |
| fegen | ein heller Balken faehrt durch |
| schreibmaschine | Zeile fuer Zeile, mit Cursorblock |
| matrix | Zeichenregen ueber den ganzen Schirm; wo er das Wort streift, bleibt es stehen |
| feuerwerk | Raketen steigen, zerplatzen, die Funken sinken auf ihre Plaetze |
| schwarzesloch | alles wird in die Mitte gesogen und wieder ausgeworfen |
| strahlen | Lichtbalken waagerecht und senkrecht |
| brennen | das Wort brennt von unten nach oben an |
| schnitt | waagerecht durchgeschnitten, beide Haelften fahren ein |

TTE, das Omarchy benutzt, bringt **39** mit -- so viele werden es hier nicht.
Die zehn decken die Spielarten ab, die auf neun Zeilen ueberhaupt zur Geltung
kommen; der Rest von TTEs Liste lebt von grossen Bildern.

Der Schriftzug ist aus der eigenen Schrift **gerastert**, nicht von Hand gemalt
-- so sitzen die Proportionen. Die Farbe kommt aus `palette.sh`, also aus dem
laufenden Theme: nach einem Themewechsel hat der Schoner denselben Akzent wie
die Leiste.

Zwei Dinge, die dabei zaehlen:

- **Der Titel steht schon beim Oeffnen.** niri wertet seine Fensterregel aus,
  sobald das Fenster auftaucht -- zu dem Zeitpunkt hiess es noch "ghostty", und
  `open-fullscreen` griff nie. Dass das Skript den Titel spaeter selbst setzt,
  kam fuer die Regel zu spaet; er wird deshalb schon auf der Befehlszeile
  mitgegeben (`--title=`), dazu `--fullscreen=true`. Ueber die App-Kennung
  ginge es gar nicht: ghostty vergibt die fest, `--class` aendert daran nichts
  (geprueft mit 1.3.1).
- **Beendet wird auf zwei Wegen.** Das Skript steigt bei Tastendruck und
  Mausbewegung aus; zusaetzlich schickt nbshell ein SIGTERM, sobald der
  Leerlauf endet. Das zweite ist noetig, weil eine Mausbewegung ausserhalb des
  Terminalfensters dort nie ankommt.

### Der Kaffee-Knopf

Der Baustein `caffeine` sitzt neben der Uhr. Klick haelt den Rechner wach,
noch ein Klick laesst die Automatik wieder zu; Rechtsklick schaltet die
Automatik ganz ab. Das Popout nennt die drei Fristen, damit man nachsehen
kann, wann was passiert waere.

**Sichtbar ist er nur, wenn er an ist** -- als gelbe Tasse. Das ist der ganze
Trick: ein Knopf, der dauernd dasteht, wird zu Moebel, und dann vergisst man,
dass der Rechner seit drei Tagen wachgehalten wird. Er steht deshalb auch in
`collapsedWidgets`: in der zugeklappten Insel, neben der Uhr, sieht man den
Kaffee auch dann, wenn sonst nichts zu sehen ist.

Der Zustand liegt in der Config (`caffeine`), nicht nur im Speicher: wer den
Rechner wachhaelt, weil ein langer Lauf durchgeht, will nicht, dass ein
`install.sh` das stillschweigend zuruecknimmt.

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

### Warnen, bevor es zu spaet ist

Die Zelle wurde bei 20 % rot -- und das war alles. Steht die Insel zugeklappt
auf der Uhr, sieht man davon nichts, und der Rechner geht irgendwann einfach
aus. Jetzt kommt eine Meldung an festen Schwellen (`batteryWarnAt`,
Vorgabe `[20, 10, 5]`), unter 5 % als `critical`.

Jede Schwelle meldet sich **genau einmal je Entladung**: ohne das Merken kaeme
bei 19,6 / 19,4 / 19,2 % dreimal dieselbe Meldung. Zurueckgesetzt wird beim
Anstecken. Und wer aus dem Standby mit 4 % aufwacht, bekommt eine Meldung, nicht
drei -- gemeldet wird nur die niedrigste erreichte Schwelle.

### Akkus der Geraete

Der Baustein `devices` zeigt das **schwaechste** angeschlossene Bluetooth-Geraet
-- Maus, Kopfhoerer, Tastatur --, sein Popout alle. Die Zahlen lagen laengst
vor (BlueZ meldet sie, wie die WLAN-Staerke als Anteil zwischen 0 und 1), sie
standen nur ganz unten in der Geraeteliste des Control Centers, wo sie niemand
sieht.

Die Zelle ist **still, solange alles ueber 30 % steht** (`deviceLowAt`) und
meldet sich je Geraet einmal, wenn es unter 15 % faellt (`deviceWarnAt`).
Erneut erst, wenn es wieder ueber 25 % war -- sonst haengt eine Maus, die um
die Schwelle pendelt, den ganzen Tag in den Meldungen.

Das USB-Headset steht dort **nicht**: das ist kein Bluetooth-Geraet und kommt
weiter ueber das `headset`-Plugin.

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

**Ein Rechtsklick auf die Uhr wechselt ihr Format** und geht dabei reihum durch
`clockFormats`: lang, kurz, Kalenderwoche, 12 Stunden mit AM/PM. Uebernommen
aus Omarchy 4, wo die Uhr dasselbe kann. `%W` ist der einzige eigene
Platzhalter — Qts Locale-Formate kennen keine Kalenderwoche, die rechnet
`Calendar.isoWeek()` aus (dieselbe Funktion, die das Monatsgitter benutzt; sie
zweimal zu haben hiesse, sie zweimal unterschiedlich falsch zu haben).

```bash
nbshell set clockFormat "'KW'%W  ddd  HH:mm"     # KW32  So.  11:33
nbshell set clockFormats '["HH:mm","ddd dd.MM  HH:mm"]'
```

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

## Aufgaben

Der Baustein `todo` zeigt, wie viele Punkte offen sind; sein Popout die Liste,
Klick hakt ab, Rechtsklick wirft weg. Zum Eintragen braucht es ein
Eingabefeld und damit die Tastatur -- die gehoert in einem Popout dem Fenster
darunter, deshalb gibt es dafuer ein eigenes Fenster: **Mod+T**.

```
AUFGABEN                                    2 offen  ·  1 erledigt
> neue Aufgabe eintippen, Enter legt sie an
────────────────────────────────────────────────────────────────
▸ [ ] Fahrradschlauch flicken                              07.08.
  [ ] Vom Telefon eingetragen                              07.08.
  [x] M̶i̶l̶c̶h̶ ̶k̶a̶u̶f̶e̶n̶                                          07.08.
Tab hakt ab · ↑↓ waehlen · Strg+E aendern · Strg+D loescht · Strg+L raeumt auf
```

Das Eingabefeld hat immer den Fokus -- man soll losschreiben koennen, ohne
vorher irgendwohin zu klicken. Deshalb liegt jede Aktion auf einer Taste, die
beim Tippen nicht im Weg ist. **Ein blankes „Leertaste hakt ab" gaebe es keine
Aufgabe mit einem Leerzeichen darin.**

Ohne Baustein in der Leiste geht es auch: `nbshell todo Muell rausbringen`
traegt aus dem Terminal ein, `nbshell todo` listet auf.

### Abgleich mit dem Telefon

Die Liste ist **eine JSON-Datei**, sonst nichts. Wer sie in einen Ordner legt,
den ein Abgleich mitnimmt (Syncthing, Nextcloud, Dropbox), hat sie auf jedem
Geraet:

```bash
nbshell set todoFile '~/Sync/nbshell/todo.json'
```

Steht dort nichts, liegt sie unter `~/.local/state/nbshell/todo.json` und
bleibt, wo sie ist. Der eingestellte Pfad steht in der Ueberschrift des
Fensters -- „auf der falschen Datei gearbeitet" ist sonst der haeufigste Grund,
warum nichts ankommt.

Auf dem Telefon macht das der [nblauncher](https://github.com/nerdislb/nblauncher)
mit: unter `# settings` -> `## todo sync` waehlt man **den Ordner** (nicht die
Datei -- ein Abgleich, der `todo.json` ersetzt statt sie zu aendern, macht eine
Berechtigung auf die einzelne Datei ungueltig), und darin findet er `todo.json`.
Abgeglichen wird beim Start, bei jeder Aenderung und jedes Mal, wenn der
Launcher wieder in den Vordergrund kommt -- bei einem Homescreen ist das der
billigste denkbare Auslöser.

Das Format ist das des nblauncher, erweitert um drei Felder:

```json
[
  {
    "id": 1786085468073,
    "text": "Fahrradschlauch flicken",
    "done": false,
    "created": 1786085468073,
    "updated": 1786085468073,
    "deleted": false
  }
]
```

`id` ist der Zeitpunkt des Eintragens in Millisekunden -- dasselbe, was
`System.currentTimeMillis()` vergibt. Ein Leser, der nur `id`, `text` und
`done` kennt, kann die Datei unveraendert lesen; die drei Zusatzfelder
ignoriert er.

**Zwei Regeln, und beide sind der Grund, dass beim Abgleich nichts verloren
geht:**

*Die Datei wird nicht ersetzt, sondern eintragsweise zusammengefuehrt.* Bei
gleicher `id` gewinnt der groessere `updated`-Stempel. Wer stattdessen die
ganze Datei uebernimmt, verliert jedes Mal alles, was auf dem Telefon
dazukam, waehrend der Rechner aus war: die Datei kaeme vollstaendig an und
wuerde von der eigenen, aelteren Fassung ueberschrieben.

*Geloescht wird mit `deleted: true`, nicht durch Weglassen.* Ein fehlender
Eintrag ist von einem „auf der anderen Seite noch nicht bekannten" nicht zu
unterscheiden -- ein weggelassener Eintrag kaeme beim naechsten Abgleich also
wieder zurueck. Die Grabsteine verfallen nach `todoKeepDays` Tagen (Vorgabe
30); so lange hat auch ein Telefon Zeit, das drei Wochen im Flugmodus lag.

Ein Eintrag **ohne** `updated` gilt als uralt (Stempel 0). Neu ist er trotzdem
immer, wenn seine `id` hier noch niemand kennt -- eine Seite, die keine Stempel
schreibt, kann also Aufgaben schicken, aber keine Aenderung an einer
bestehenden durchsetzen.

### Eine leere Datei heisst nicht „leer"

Der Fehler, der beim Ausprobieren wirklich einen Eintrag gekostet hat, und
zwar in **beiden** Programmen zugleich:

Wer eine Datei ersetzt, ohne sie vorher unter einem anderen Namen
fertigzuschreiben, **kuerzt sie zuerst auf 0 Bytes**. `adb pull` tut das, `cp`
tut das, mancher Abgleich auch. Wird genau dieser Moment gelesen und als „die
andere Seite hat alles geloescht" verstanden, gewinnt die eigene Seite jeden
Vergleich -- und schreibt ihren Stand ueber eine Datei, die gerade erst zur
Haelfte angekommen ist. Der Eintrag vom Telefon war weg, ohne eine einzige
Fehlermeldung.

Deshalb gilt hier wie im Launcher: **leerer oder unlesbarer Inhalt ist keine
Information.** Dann passiert nichts, und beim naechsten Mal wird noch einmal
hingesehen. Wirklich leer geraeumt wird als `[]` geschrieben -- das ist Text
und faellt nicht darunter. Dazu wartet die Shell nach einer gemeldeten
Aenderung 300 ms, bevor sie liest: das faellt mit den Meldungen mehrerer
Schreibschritte zu einem Lesen zusammen.

### Konfliktkopien

Ein Dateiabgleich kann zwei gleichzeitige Aenderungen nicht aufloesen. Er
behaelt eine Fassung und legt die andere daneben:

```
todo.sync-conflict-20260807-101500-ABCDEFG.json
```

Wer sie liegen laesst, verliert alles, was nur in ihr steht.
`scripts/todo.sh merge` faltet sie nach derselben Regel zurueck (gleiche `id`
-> groesserer `updated`) und loescht sie danach. Aufgerufen wird das beim
Start, bei jeder Aenderung an der Datei und beim Oeffnen des Fensters -- von
Hand: `nbshell todo sync`. Laesst sich eine Kopie nicht lesen, bleibt sie
liegen; lieber eine Datei zuviel als eine Liste kaputt.

Syncthing gehoert seit diesem Baustein zu den Paketen in `setup.sh` und laeuft
als **Benutzerdienst** (`systemctl --user enable --now syncthing`) -- die
Dateien gehoeren dem Benutzer.

## In der Naehe (LocalSend)

```bash
nbshell nearby scan               # wer ist da
nbshell nearby                    # gefundene Geraete
nbshell nearby send <datei> [alias]
```

Der Baustein `nearby` zeigt, wie viele Geraete gerade erreichbar sind; sein
Popout listet sie mit zwei Knoepfen je Geraet: **Zwischenablage** und
**letztes Bild**. Das sind die beiden Dinge, die man tatsaechlich schnell
hinueberschiebt; alles andere geht ueber die Befehlszeile, weil ein
Dateiwaehler in einer Leiste zwei Bedienungen zu viel waere.

Die Idee stammt aus dem [Omarchy-Plugin-Katalog](https://omarchyplugins.com)
(`Nearby` von jfg96). Dort erledigt ein **vorkompilierter Rust-Helfer** die
Arbeit; hier reicht `python3`, das ohnehin Pflicht ist. Das Protokoll steht in
`scripts/nearby.py`: Multicast-Erkennung, `register`, `prepare-upload`,
`upload` -- rund 300 Zeilen Standardbibliothek, kein Paket, kein Kompilat.

**Gesucht wird nur, solange das Popout offen ist.** Eine Suche im Hintergrund
hiesse: alle paar Sekunden ein Multicast-Paket ins WLAN, den ganzen Tag, fuer
eine Liste, die niemand ansieht. Dieselbe Regel wie beim Bluetooth-Scanner.

Und einmal rufen statt nur lauschen: LocalSend kuendigt sich vor allem beim
Start an. Wer nur wartet, sieht ein Telefon, das seit zehn Minuten offen ist,
nie -- die Ankuendigung mit `announce: true` ist die Aufforderung zu antworten.

### Was es NICHT kann: empfangen

Dafuer braeuchte es einen dauerhaft laufenden HTTPS-Server mit eigenem
Zertifikat, eine Zustimmungsabfrage und einen offenen Port in der Firewall.
Das ist ein eigenes Stueck Arbeit; zum Empfangen bleibt die LocalSend-App.
Zum schnellen Hinschicken braucht es sie nicht mehr.

Alle Gegenstellen sprechen HTTPS mit **selbstsigniertem** Zertifikat, geprueft
wird es deshalb nicht. Das ist kein Versehen: im Protokoll ist der
Fingerabdruck die Kennung, keine Zertifikatskette. Der eigene liegt in
`~/.local/state/nbshell/nearby.json` und bleibt -- wechselt er, ist man fuer
die Gegenstelle ein neues, unbekanntes Geraet.

Ohne Ziel schickt `nbshell nearby send` nur, wenn genau EIN Geraet gefunden
wurde. Bei mehreren nennt es die Namen und verlangt eine Entscheidung: wortlos
das erste zu nehmen waere die Sorte Hilfsbereitschaft, die Dateien an Fremde
schickt.

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

### Passwoerter kommen hier nicht an

Wer ein Geheimnis in die Zwischenablage legt, haengt dem Angebot den Mime-Typ
`x-kde-passwordManagerHint` an — KeePassXC, 1Password, Bitwarden und die
uebrigen tun das. Der Wachhund fragt die Typen des laufenden Angebots ab
(`wl-paste --list-types`) und schweigt dann.

Das ist kein Feinschliff, sondern der Unterschied zwischen „das Passwort
verfaellt in der Zwischenablage nach Sekunden" und „das Passwort steht im
Klartext in `~/.local/state/nbshell/clipboard.json`, bis fuenfzig andere
Eintraege es hinausgeschoben haben". Uebernommen aus Omarchy 4
(„sensitive-content exclusion").

Gelesen wird immer, auch wenn nichts gespeichert wird: `wl-paste --watch`
schiebt den Inhalt in die Standardeingabe des Befehls, und wer sie nicht leert
und einfach aussteigt, schickt dem Wachhund ein SIGPIPE.

Abschalten kann man den Schutz mit `clipboardGuardSecrets: false` — sinnvoll
ist das eigentlich nie.

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

**Das aktuelle Bild steht in voller Groesse, die uebrigen sind eingerueckt und
auf 45 % gedaempft.** Ein staerkerer Rahmen allein reichte nicht — auf einem
Streifen aus Fotos verschwindet er zwischen den Bildinhalten.

Der Streifen **gleitet** beim Blaettern, statt zu springen: er folgt ueber
`currentIndex` und einen Vorzugsbereich in der Mitte (`ApplyRange`), nicht ueber
`positionViewAtIndex` — das setzt `contentX` hart und ueberfaehrt genau die
Bewegung, die man sehen soll. Nur beim Oeffnen wird hart gesprungen: eine
Animation aus dem Nichts sieht aus, als haette man schon etwas verstellt.

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

### Vier Bausteine, aus denen sie bestehen

Bis vor kurzem baute jedes Popout seine Zeilen selbst — mit von Hand gesetzten
Spalten (`anchors.leftMargin: Theme.cellW * 17`), einer eigenen `Heading`-Komponente
je Datei und Abschnitten, die nur durch Abstand getrennt waren. Beim Durchsehen
von Omarchy 4 fiel auf, dass deren Panels genau vier Muster wiederholen. Die
stehen jetzt in `shell/Widgets/` und gelten fuer alle:

| | |
|---|---|
| `Facts` | Kennwerte als Raster: Beschriftung gedimmt links, Wert hell rechts, zwei Paare je Zeile |
| `Rule` | Haarlinie, wahlweise mit Ueberschrift darunter — das `---` einer Manpage |
| `Segments` | Reihe gerahmter Kaestchen, das aktive gefuellt |
| `PanelHead` | Symbol, Titel, gedimmter Untertitel, gerahmte Marke rechts |

**`Facts` ist der groesste Gewinn.** Acht Werte passen damit auf vier Zeilen,
und die Zahlen stehen in beiden Spalten untereinander — der Wert sitzt am
rechten Rand *seiner* Spalte, nicht am Rand des Popouts. Weicht der Platz
nicht, weicht die **Beschriftung**: eine abgeschnittene Zahl ist wertlos, ein
abgeschnittenes Wort noch lesbar.

```
CPU          62.0 °C   Gehaeuse       25.0 °C
SSD          36.9 °C   Chipsatz       62.0 °C
WLAN         51.0 °C   CPU-Kern (max) 62.0 °C
Luefter 1         aus  Luefter 2          aus
```

**`Segments` beantwortet eine Frage, die vorher niemand beantwortet hat:** was
es sonst noch gaebe. Die Energieprofile standen als Liste untereinander, die
Form der Leiste schaltete ein Klick blind weiter. Nebeneinander sieht man beides
auf einmal — alle Moeglichkeiten, und welche gilt. Ein `Flow` und keine `Row`:
tuneds Profile heissen Dinge wie `throughput-performance`, drei davon
nebeneinander waeren breiter als jedes Popout, also brechen sie um.

**`PanelHead`** trennt Sache und Zusammenhang (`Magentanpjuda` / `WLAN`) und
setzt die eine Zahl, die man ohne Lesen erkennen will, als Marke an den rechten
Rand — Signalstaerke, Ladestand, Temperatur der Grafikkarte, Anzahl der Themes.
Nur dort, wo rechts nichts anderes steht: im Update-Popout sitzen da die
Knoepfe, und zwei Dinge am selben Rand sind eines zu viel.

Was **nicht** uebernommen wurde: Transparenz, weiche Ecken, Schlagschatten —
und vor allem der Groessensprung. Omarchys Wetter-Panel setzt die Temperatur
dreimal so gross wie alles andere. Das sieht gut aus und bricht die Regel, die
unsere Leiste zusammenhaelt: alles ist eine Zeichenzelle hoch.

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
Hintergrundbild, Einblendung, Benachrichtigungsserver, Zwischenablage,
Aufgaben und Terminalfarben — gegliedert in LEISTE, AUSSEHEN, VERHALTEN und
DIENSTE.
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

**Zwei Spalten**, seit die Liste ueber vierzig Zeilen lang war: links die
Gruppen (LEISTE, BAUSTEINE, AUSSEHEN, VERHALTEN, DIENSTE), rechts ihre Zeilen.
`Tab` wechselt die Seite, `↑↓` waehlt auf der Seite, die gerade dran ist, `←→`
aendert. Eine Wurst aus Ueberschriften und Zeilen liest sich ab einer gewissen
Laenge nicht mehr — man scrollt an der Ueberschrift vorbei und weiss nicht
mehr, wo man ist.

Zwei Kleinigkeiten, die den Unterschied machen:

- **Nur die aktive Seite ist markiert.** Waeren beide Auswahlen gleich
  hervorgehoben, saehe man nicht, wo die naechste Taste landet. Die andere
  Seite behaelt nur ihren `▸`-Zeiger. Aus demselben Grund stehen die
  `◂ ▸`-Pfeile am Wert nur, wenn die rechte Seite dran ist — links kaeme
  `←→` gar nicht an.
- **Der Kasten behaelt seine Hoehe.** Sie richtet sich nach der groessten
  Gruppe, nicht nach der offenen. Sonst spraenge er beim Wechseln zwischen vier
  und neun Zeilen hin und her, und die Gruppenliste links wanderte mit.

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
`volume`, `control`, `tray`, `notifications`, `clipboard`, `todo`, `media`,
`capture`, `ai`, `updates`, `sep`.

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

### Fremde Plugins hereinholen

```bash
nbshell plugin add https://github.com/jemand/nbshell-uhrzeit
nbshell plugin add ~/basteln/mein-widget mein-widget
nbshell plugin update            # alle geklonten nachziehen
nbshell plugin remove uhrzeit
```

Nach Omarchys `omarchy plugin add <git-url>`. Geklont wird **flach** in ein
Nebenverzeichnis, dort geprueft (`manifest.json` da? Einstiegsdatei da?) und
erst dann an seinen Platz geschoben — ein halb geklontes oder falsches Repo
soll nicht als Baustein gelten, nur weil es im Ordner liegt. Ein vorhandenes
Plugin wird nie ueberschrieben; `.git` bleibt liegen, sonst koennte `update`
nichts nachziehen.

> **Ein Plugin ist QML, das IN der Shell laeuft.** Es kann alles, was die Shell
> kann: Dateien lesen, Programme starten, die Zwischenablage sehen. Es gibt
> keine Sandbox und es wird auch keine geben — `nbshell plugin add` sagt das
> vor dem Klonen noch einmal. Nur hereinholen, was du gelesen hast oder wem du
> traust.

`add`, `update` und `remove` gehen direkt an `scripts/plugins.sh` und nicht
ueber IPC: sie muessen auch dann gehen, wenn die Shell gerade nicht laeuft.

Mitgeliefert werden drei: **`beispiel`** als Vorlage (zaehlt Klicks, sonst
nichts), **`wetter`** — Temperatur in der Leiste, Einzelheiten und fuenf
Tage im Popout — und **`headset`** — Akkustand eines USB-Headsets, ueber
`headsetcontrol` (Logitech & andere mit HID++-Akkumeldung). Der Ort fuers
Wetter steht in der Config:

```bash
nbshell set weatherPlace Graz
nbshell popout wetter          # aufklappen, auch fuer eine Taste in niri
```

**Das Headset-Plugin zeigt sich nur, wenn ein Geraet wirklich antwortet** --
aus, Dongle nicht da oder ein Modell ohne `CAP_BATTERY_STATUS` heisst: die
Zelle bleibt weg, statt mit "—" herumzustehen. Was `headsetcontrol` selbst
nicht auslesen kann -- etwa ein rein analoges Lautstaerkerad am Headset --
bleibt fuer jede Software unsichtbar, das ist keine Einschraenkung des
Plugins.

**Das Wetter-Plugin und die Updatepruefung sind die einzigen Teile von nbshell,
die von sich aus ins Netz gehen.**  (Die Updatepruefung holt Paketdatenbanken
und fragt Flathub -- das ist ihre Aufgabe; siehe „Updates".) Es fragt [open-meteo.com](https://open-meteo.com) — ohne Schluessel,
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
  Services/Apps.qml    .desktop-Eintraege, Suche, Starten (je Scope)
  Services/Commands.qml  die Befehlspalette: was die Shell selbst kann
  Services/Net.qml     NetworkManager ueber Quickshell
  Services/Bt.qml      BlueZ ueber Quickshell
  Services/Brightness.qml  sysfs lesen, logind setzen
  Services/Osd.qml     Zustand der Einblendung
  Services/Notify.qml  Benachrichtigungsserver, Archiv
  Services/Session.qml Sperren, Abmelden, Ausschalten
  Services/Clipboard.qml  Verlauf ueber wl-paste --watch
  Services/Todo.qml    Aufgabenliste: lesen, zusammenfuehren, schreiben
  Todo/TodoList.qml    das Fenster dazu (Mod+T)
  scripts/todo.sh      Konfliktkopien des Abgleichs zurueckfalten
  Services/MediaService.qml  MPRIS
  Widgets/LevelBar.qml Balken aus Bloecken
  Widgets/Facts.qml    Kennwerte als Raster (Label links, Wert rechts)
  Widgets/Rule.qml     Haarlinie mit Ueberschrift
  Widgets/Segments.qml Reihe gerahmter Kaestchen, das aktive gefuellt
  Widgets/PanelHead.qml  Kopfzeile: Titel, Untertitel, Marke
  Widgets/ThemePreview.qml  Miniatur der Leiste in fremden Farben
  Net/QrWindow.qml     das WLAN als QR-Code
  Net/SpeedWindow.qml  Durchsatz als Balken
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
  Services/Cursor.qml  Zeigerthema: Config -> niri und GTK
  Services/Nearby.qml  Geraete in der Naehe, senden
  scripts/nearby.py    das LocalSend-Protokoll (Erkennung, Senden)
  scripts/cursors.sh   welche Themen es gibt, und eines setzen
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

- **Eine Property darf nicht `data` heissen.** `data` ist die Standard-
  Kindliste jedes QtObject. Eine eigene Property dieses Namens verdeckt sie --
  die Kinder des Fensters landen dann in einer Variablen statt in der Szene.
  Das Fenster liegt an (`niri msg -j layers` zeigt es), nimmt die Tastatur und
  ist vollstaendig leer. Keine Fehlermeldung, nichts.
- **Was an einem `IpcHandler` haengt, will Quickshell ueber IPC anbieten.**
  Zwei Hilfslisten als `property var` darin genuegten fuer „Type QVariant
  cannot be used across IPC" bei jedem Start. Sie gehoeren daneben, nicht
  hinein.
- **Die Signalstaerke ist ein Anteil, kein Prozent.** Quickshell liefert
  `signalStrength` zwischen 0 und 1 — wie `battery` bei Bluetooth-Geraeten.
  `Net.bars()` rechnete mit 0..100 und rundete damit **jedes** Netz auf einen
  Balken ab; das sah aus wie schlechter Empfang im ganzen Haus und war ein
  Rechenfehler. Aufgeflogen ist es erst, als die Zahl selbst in einer
  Kopfzeile stand: „0.78 %". Umgerechnet wird jetzt nachsichtig — kommt
  irgendwann doch ein Wert ueber 1, gilt er als Prozent.
- **Ein Screenshot direkt nach dem Neustart zeigt die alte Shell.** Zwischen
  „Dienst aktiv" und „Leiste gezeichnet" liegen ein bis zwei Sekunden, in denen
  die vorige Instanz noch auf dem Schirm steht. Zwei Aenderungen galten
  deshalb kurz als wirkungslos, obwohl die Dateien laengst richtig waren.
- **Eine Zelle nimmt nur Klicks an, wenn sie `interactive` ist.** Die
  `MouseArea` in `Cell.qml` haengt an `clickable` (`interactive || popout`) —
  auch der RECHTE Klick. Die Uhr stand auf `interactive: Config.value("calendar")`,
  und ohne khal waere ihr neuer Rechtsklick fuer den Formatwechsel ein totes
  Feld gewesen, ohne dass irgendwo etwas gemeldet haette.
- **Die id einer Benachrichtigung wiederholt sich.** Der Server faengt nach
  einem Neustart wieder bei 1 an. Solange alles im Speicher lag, fiel das nicht
  auf; mit einem Archiv auf der Platte haette eine frische Meldung dieselbe id
  wie eine alte — und ein Klick raeumte beide weg. Deshalb `key` aus Zeitpunkt
  und id.
- **`wl-paste --watch` will, dass man liest.** Der Inhalt kommt in der
  Standardeingabe des aufgerufenen Befehls. Wer sie nicht leert und einfach
  aussteigt (etwa weil er ein Passwort nicht speichern will), schickt dem
  Wachhund ein SIGPIPE. Erst lesen, dann verwerfen.
- **`./install.sh | head` liess die Leiste weg.** Das Skript stoppt den Dienst,
  tauscht das Verzeichnis und startet ihn am Ende wieder. Schliesst `head` die
  Pipe vorher, faellt es unter `set -o pipefail` mit SIGPIPE aus — genau
  zwischen „gestoppt" und „gestartet". Jetzt holt ein `trap … EXIT` die Leiste
  in jedem Abbruchfall zurueck.
- **`A || B && C` ist unter `set -e` eine Falle.** Schlagen A und B fehl, ist
  der Rueckgabewert der Zeile 1 — und die Funktion endet dort, still und ohne
  Meldung. In `text_size` stand genau das (`[ -z "$x" ] || [ "$x" = null ] && x=13`);
  daraus wurde ein `if`.
- **Ein `Behavior` braucht eine schreibbare Property.** Auf einer
  `readonly property` scheitert er mit „is a read-only property" — und weil
  das ein Ladefehler ist, faellt der ganze Typ aus und die Shell startet nicht
  mehr. Beim Animieren schreibt der Behavior die Property ja selbst.
- **Eine `MouseArea` mit `hoverEnabled` nimmt das Ueberfahren fuer sich.** Ein
  `HoverHandler` weiter oben — etwa der des Popoutfensters — sieht es dann
  nicht mehr, haelt die Maus fuer verschwunden und startet den Nachlauf: nach
  2,5 s klappt das Popout zu, mitten im Lesen. Im Kalender faellt das auf, weil
  man dort laenger auf einer Zelle verweilt. In Popouts gehoeren deshalb
  `HoverHandler` und `TapHandler` hin; Handler blockieren einander nicht.
- **Eine Datei, die gerade geschrieben wird, ist erst leer.** Wer eine Datei
  beobachtet und ihren Inhalt als Wahrheit nimmt, liest frueher oder spaeter
  0 Bytes -- und haelt das fuer eine geleerte Liste. Siehe „Aufgaben"; es hat
  einen Eintrag gekostet.
- **Ein Baustein darf nicht heissen wie sein Dienst.** `Bar/Widgets/Todo.qml`
  neben dem Singleton `Todo` aus `qs.Services`: beide Namen liegen in
  `WidgetHost.qml` im selben Gueltigkeitsbereich, und `Todo {}` ist dann
  mehrdeutig. Deshalb `Tasks` (Baustein) neben `Todo` (Dienst) — dieselbe
  Trennung, die es bei `Clip` und `Clipboard` schon gab. In der Config heisst
  der Baustein trotzdem `todo`; die Dateinamen interessieren dort niemanden.
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
