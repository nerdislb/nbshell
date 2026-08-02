# nbshell

Eine eigene Shell fuer Wayland, gebaut auf [Quickshell](https://quickshell.org)
und niri.

Kern ist eine **Insel**, die bei Bedarf zum **durchgehenden Balken** aufmacht.
Das Aussehen orientiert sich an [Omarchy](https://omarchy.org) und an einer
Terminaloberflaeche: Monospace, gerade Kanten, 1 px Rahmen, Farben aus derselben
Palette wie das Terminal. Kein Material Design.

Stand: **1.5.0** — alles, was vorher als DMS-Plugin lief, ist jetzt hier. Es laeuft: Insel und Balken, Popouts, Themewahl mit
Farbproben, Hintergrundbild am Theme, Audio, Control Center, Anwendungsstarter, Einblendung, System-Tray, Benachrichtigungen, Power-Menue, Zwischenablage, Medien, Prozessliste, Aufnahme, Terminalfarben, KI-Verbrauch, Optionsmenue, Arbeitsflaechen, Fenstertitel, Uhr, Systemlast, Tastaturbelegung,
Akku. Alles Weitere steht unter „Was noch fehlt".

## Installieren

```bash
./install.sh
nbshell start -d
```

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
nbshell island           # freistehende Insel
nbshell mode toggle
nbshell edge top|bottom|toggle
nbshell open|close|toggle   # Insel festhalten, unabhaengig von der Maus

nbshell theme            # aktuelles Theme
nbshell theme gruvbox    # wechseln
nbshell themes           # alle auflisten
nbshell theme install <url|verzeichnis>
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
nbshell ai               # KI-Verbrauch (auch: refresh)
nbshell capture          # Aufnahme-Menue (screen, window, region, ocr, record)
nbshell procs            # Prozessliste; `nbshell procs top` als Text
nbshell power            # Power-Menue (auch: lock, logout, suspend)
nbshell clip             # Zwischenablage (toggle, list, clear)
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
Mod+Shift+I hotkey-overlay-title="nbshell: Insel/Balken" {
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

Zwei Entscheidungen bestimmen alles andere.

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

Einstellbar in `config.json`: `theme`, `font`, `fontSize`, `mode`, `edge`,
`gap`, `lines`, `padX`, `padY`, `radius`, `borderWidth`, `opacity`,
`widgetStyle` (`box` | `bracket` | `plain`), `widgetColor` (`text` | `accent`),
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
nbshell theme update          # selbst installierte per git pull
nbshell theme remove <name>
nbshell theme list            # mitgeliefert vs. selbst installiert
```

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

Er kuemmert sich um drei Dinge, die zusammengehoeren:

1. **`dms.service` stoppen.** `disable` hilft dabei NICHT: DMS haengt ueber ein
   Drop-in an `niri.service`
   (`~/.config/systemd/user/niri.service.d/dms.conf`, `Wants=dms.service`) und
   kommt bei jeder Anmeldung wieder. Dauerhaft weg bleibt es nur mit `mask` --
   und das nur auf ausdrueckliche Ansage.
2. **Den Benachrichtigungsserver umlegen.**
3. **Die Tastenkuerzel**, die bisher DMS gehoerten: `niri/nbshell-takeover.kdl`
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

Der Baustein `tray` zeigt die Symbole der Programme, die sich per
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
`ai`, `sep`.

Vier Listen sagen, was wo steht:

```json
"collapsedWidgets": ["clock"],
"leftWidgets":  ["workspaces", "sep", "window"],
"centerWidgets": ["clock"],
"rightWidgets": ["sys", "sep", "layout", "battery"]
```

`collapsedWidgets` ist die zugeklappte Insel. Die anderen drei sind der
Balken — und die aufgeklappte Insel zeigt sie hintereinander.

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

**Insel und Balken sind dasselbe Fenster.** Es ist immer bildschirmbreit und
durchsichtig; nur der Rahmen darin waechst, und eine `Region`-Maske haelt die
durchsichtige Flaeche klickdurchlaessig. Der Unterschied ist fast nur
Geometrie — plus die `exclusiveZone`: als Balken reserviert die Leiste ihren
Platz und schiebt die Fenster weg, als Insel schwebt sie darueber.

**Die drei Gruppen gibt es nur einmal.** Sie sitzen in einer Reihe, deren zwei
Zwischenraeume ihre Breite wechseln: im Balken so gerechnet, dass die Mitte
wirklich mittig steht, in der Insel auf einen Zeichenabstand. So muss nichts
doppelt gebaut werden, und der Uebergang laesst sich animieren.

## Fallstricke

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
