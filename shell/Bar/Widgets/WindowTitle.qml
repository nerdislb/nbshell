import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Titel des aktiven Fensters, auf eine feste Zeichenzahl gekuerzt.
//
// Gekuerzt wird in Zeichen, nicht in Pixeln: bei Monospace ist das dasselbe,
// und die Leiste haelt so ihre Breite, statt bei jedem Fensterwechsel zu
// zappeln.
Cell {
    id: root

    readonly property int maxChars: Config.value("titleLength", 40)
    readonly property string title: Compositor.focusedTitle

    shown: title !== ""
    color: Theme.textDim
    text: title.length > maxChars ? (title.substring(0, maxChars - 1) + "…") : title
}
