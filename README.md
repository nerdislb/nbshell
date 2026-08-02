# nbshell

Eine eigene Shell fuer Wayland, gebaut auf [Quickshell](https://quickshell.org)
und niri.

Kern ist eine **Insel**, die bei Bedarf zum **durchgehenden Balken** aufmacht.
Das Aussehen orientiert sich an [Omarchy](https://omarchy.org) und an einer
Terminaloberflaeche: Monospace, gerade Kanten, 1 px Rahmen, Farben aus derselben
Palette wie das Terminal. Kein Material Design.

Stand: **0.10.0.** Es laeuft: Insel und Balken, Popouts, Themewahl mit
Farbproben, Hintergrundbild am Theme, Audio, Control Center, Anwendungsstarter, Einblendung, System-Tray, Benachrichtigungen, Arbeitsflaechen, Fenstertitel, Uhr, Systemlast, Tastaturbelegung,
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
nbshell themes           # alle 21 auflisten
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

nbshell control          # Control Center
nbshell brightness up | down | 60

nbshell wallpaper on     # Hintergrundbild des Themes
nbshell wallpaper ~/bild.jpg   # festes Bild stattdessen

nbshell set fontSize 15
nbshell set rightWidgets '["sys","sep","battery"]'
nbshell config           # ganze Config zeigen
nbshell status
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
`widgetStyle` (`box` | `bracket` | `plain`), `collapseDelay`, `clockFormat`,
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

**Was danach tot bleibt**, weil nbshell es noch nicht kann: Zwischenablage
(`Mod+V`), Power-Menue (`Super+X`), Sperrbildschirm (`Mod+Alt+L` -- dafuer
hyprlock von Hand binden), Prozessliste (`Mod+M`) und die Medientasten
Play/Next/Prev (kein MPRIS). Die Liste steht auch im Kopf der
Takeover-Datei.

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

## Bausteine

`clock`, `workspaces`, `window`, `sys`, `battery`, `layout`, `themes`,
`volume`, `control`, `tray`, `notifications`, `sep`.

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
  Widgets/LevelBar.qml Balken aus Bloecken
  Widgets/MenuView.qml DBus-Menues als Liste
  Widgets/Cell.qml     der eine Baustein, aus dem alles besteht
  Bar/Bar.qml          das Fenster: Insel oder Balken
  Bar/Wallpaper.qml    Hintergrundbild je Bildschirm
  Launcher/Launcher.qml  Anwendungsstarter
niri/nbshell-takeover.kdl  Binds fuer den Umstieg
  Osd/Osd.qml          die Einblendung je Bildschirm
  Notifications/Popups.qml  die Karten am Rand
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
- **Power-Menue**, **Zwischenablage**.
- **Anwendungslautstaerken** — die Stroeme einzelner Programme.
- **Sperrbildschirm** — hier wird bewusst nichts Eigenes gebaut; ein Fehler
  darin sperrt dich aus. hyprlock tut es.
- **Einstellungsoberflaeche** — bis dahin ist `config.json` die Oberflaeche.

## Lizenz

MIT, siehe `LICENSE`.
