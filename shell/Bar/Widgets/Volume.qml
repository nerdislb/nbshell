import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Lautstaerke. Mausrad regelt, Rechtsklick schaltet muted, Klick klappt die
// Regler und die Geraeteliste auf.
Cell {
    id: root

    shown: Audio.ready
    slotChars: 5
    interactive: true
    popoutTakesKeyboard: true
    color: Audio.muted ? Theme.red : Theme.text

    // Der Lautsprecher zeigt schon, worum es geht -- das "VOL" davor war
    // Beschriftung fuer eine Beschriftung.
    label: "VOL"
    icon: Audio.muted ? Icons.volumeMuted : (Audio.volume >= 67 ? Icons.volumeHigh : (Audio.volume >= 34 ? Icons.volumeMid : Icons.volumeLow))
    text: Audio.muted ? "--" : (Audio.volume + "%")

    // Die Schrittweite haengt daran, WIE gescrollt wurde: ein Mausrad rastet
    // und meldet 120 pro Rastung -- das sind die vollen 5 %. Ein Touchpad
    // meldet dagegen ein Dutzend kleiner Werte je Fingerbewegung; mit festen
    // 5 % waere die Lautstaerke bei der kleinsten Geste am Anschlag. Ein
    // Prozent ist die Untergrenze, sonst passierte gar nichts mehr.
    onWheel: delta => {
        const step = Math.max(1, Math.round(Math.abs(delta) / 120 * 5));
        Audio.step(delta > 0 ? step : -step);
    }
    onRightClicked: Audio.toggleMute()

    preview: Component {
        BarPreview {
            icon: Audio.muted ? Icons.volumeMuted : Icons.volumeHigh
            title: Audio.label(Audio.sink)
            subtitle: "Audio output"
            badge: Audio.muted ? "MUTED" : Audio.volume + " %"
            badgeColor: Audio.muted ? Theme.red : Theme.accent
            content: [
                LevelBar {
                    cells: 32
                    value: Audio.volume
                    maximum: Audio.maxVolume
                    fillColor: Audio.muted ? Theme.muted : Theme.accent
                    onMoved: value => Audio.setVolume(value)
                },
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Playing apps", "value": String(Audio.appStreams.length) },
                        { "label": "Microphone", "value": Audio.micMuted ? "muted" : Audio.micVolume + " %", "color": Audio.micMuted ? Theme.red : Theme.fg }
                    ]
                }
            ]
        }
    }

    // Auch per Tastenkuerzel aufklappbar -- nicht als Bindung, sonst
    // ueberschriebe sie den Klick auf die Zelle.
    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: {
        Runtime.audioPanelOpen = root.popoutVisible;
        // Den Codec erst jetzt lesen -- er interessiert nur den, der hinsieht.
        if (root.popoutVisible)
            {
                Audio.codecsLesen();
                Audio.routenLesen();
            }
    }

    popoutCloseOnLeave: false
    popoutInsetBorder: true
    popoutPadding: Theme.audioPadding
    popoutBorderWidth: Theme.audioBorderWidth
    popoutBorderColor: Theme.focusBorder
    popoutHeightLimit: Theme.audioMaxHeight - 2 * (popoutPadding + popoutBorderWidth)

    popout: Component {
        AudioPanel {
            availableWidth: root.Screen.width - Config.gap * 2 - (root.popoutPadding + root.popoutBorderWidth) * 2
        }
    }
}
