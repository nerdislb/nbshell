import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Was gerade laeuft. Klick spielt/pausiert, Mausrad blaettert durch die
// Titel, Rechtsklick stoppt.
Cell {
    id: root

    readonly property int maxChars: Config.value("mediaLength", 34)

    shown: MediaService.active
    interactive: true
    color: MediaService.playing ? Theme.text : Theme.textDim

    label: MediaService.playing ? "▶" : "❚❚"
    icon: MediaService.playing ? Icons.play : Icons.pause
    text: {
        const label = MediaService.label;
        return label.length > maxChars ? (label.substring(0, maxChars - 1) + "…") : label;
    }

    onClicked: MediaService.playPause()
    onRightClicked: MediaService.stop()
    onWheel: delta => delta > 0 ? MediaService.previous() : MediaService.next()
}
