import QtQuick
import qs.Common
import qs.Widgets

// Vorlage fuer einen eigenen Baustein.
//
// Kopieren, umbenennen, die manifest.json anpassen -- fertig. Das Verzeichnis
// liegt unter ~/.config/nbshell/plugins und ueberlebt jedes `install.sh`.
//
// Was hier zur Verfuegung steht:
//
//   qs.Common    Config, Theme, Icons, Runtime
//   qs.Widgets   Cell, Popout, IconText, Glyph, LevelBar, MenuView
//   qs.Services  Compositor, Audio, Net, Bt, Notify, MediaService, Calendar, …
//
// Die Wurzel muss `Cell` sein (oder etwas mit denselben Eigenschaften): die
// Leiste liest davon `shown`, `implicitWidth` und `implicitHeight`.
//
// **Ausblenden ueber `shown`, nicht ueber `visible`** -- die Sichtbarkeit eines
// Kindes enthaelt immer die des Elternteils, und die Huelle wuerde ihre eigene
// Antwort lesen. Beide blieben fuer immer unsichtbar.
Cell {
    id: root

    property int clicks: 0

    // `output` wird von der Leiste gesetzt, wenn der Baustein die Eigenschaft
    // hat -- der Name des Bildschirms, auf dem diese Kopie steht.
    property string output: ""

    label: "BSP"
    icon: Icons.palette
    text: root.clicks > 0 ? String(root.clicks) : ""
    color: Theme.text
    interactive: true

    onClicked: root.clicks += 1
    onRightClicked: root.clicks = 0
}
