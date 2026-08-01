# nbshell

Eine eigene Shell fuer Wayland, gebaut auf [Quickshell](https://quickshell.org)
und niri.

Kern ist eine **Insel**, die bei Bedarf zum **durchgehenden Balken** aufmacht.
Das Aussehen orientiert sich an [Omarchy](https://omarchy.org) und an einer
Terminaloberflaeche: Monospace, gerade Kanten, 1 px Rahmen, Farben aus derselben
Palette wie das Terminal. Kein Material Design.

Stand: **0.3.0.** Es laeuft: Insel und Balken, Popouts, Themewahl mit
Farbproben, Hintergrundbild am Theme, Arbeitsflaechen, Fenstertitel, Uhr, Systemlast, Tastaturbelegung,
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
`titleLength`, `locale`, `wallpaper`, `wallpaperOverride` und die vier
Bausteinlisten.

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

`clock`, `workspaces`, `window`, `sys`, `battery`, `layout`, `themes`, `sep`.

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
  Widgets/Cell.qml     der eine Baustein, aus dem alles besteht
  Bar/Bar.qml          das Fenster: Insel oder Balken
  Bar/Wallpaper.qml    Hintergrundbild je Bildschirm
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
- **Ein Positionierer rechnet seine implizite Groesse selbst aus.** `Column`
  und `Row` verweigern jede Zuweisung an `implicitWidth`/`implicitHeight`
  („read-only property") — die Breite gehoert an die Kinder.
- **Ein `Loader` darf keine eigene Groesse bekommen**, sonst skaliert er sein
  Kind darauf; setzt das Kind seine Breite selbst, fallen beide auf 0.
- **Vorgabewerte koennen Fehler verstecken.** Der TOML-Leser hat anfangs nur
  eine einzige Zeile erwischt (die Raute jeder Farbe galt als Kommentar) — und
  weil die Vorgaben ein vollstaendiges Theme sind, sah alles richtig aus. Faellt
  die Palette zu klein aus, warnt die Shell jetzt.
- **`install.sh` beendet eine laufende Instanz.** Quickshell laedt bei jeder
  Dateiaenderung neu und wuerde mitten im Austausch eine halbe Shell lesen.

## Verhaeltnis zu DMS

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bleibt
installiert und ist die Rueckfallebene, solange hier noch etwas fehlt. Beide
koennen gleichzeitig laufen — nbshell beansprucht bewusst keine D-Bus-Namen
(Benachrichtigungen, Tray). Sobald das noetig wird, muss eine von beiden weichen.

## Was noch fehlt

Der Reihe nach, wie es fuer den Alltag zaehlt:

- **Control Center** — Audio (Pipewire), Netz, Bluetooth, Helligkeit.
- **Benachrichtigungen** — der Server steckt in Quickshell, es fehlen Popups
  und Verlauf.
- **Launcher** — Anwendungssuche.
- **OSD** fuer Lautstaerke und Helligkeit, **Power-Menue**, **Zwischenablage**.
- **System-Tray.**
- **Sperrbildschirm** — hier wird bewusst nichts Eigenes gebaut; ein Fehler
  darin sperrt dich aus. hyprlock tut es.
- **Einstellungsoberflaeche** — bis dahin ist `config.json` die Oberflaeche.

## Lizenz

MIT, siehe `LICENSE`.
