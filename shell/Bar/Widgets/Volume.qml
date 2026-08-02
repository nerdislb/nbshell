import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Lautstaerke. Mausrad regelt, Rechtsklick schaltet stumm, Klick klappt die
// Regler und die Geraeteliste auf.
Cell {
    id: root

    shown: Audio.ready
    interactive: true
    color: Audio.muted ? Theme.red : Theme.text
    text: Audio.muted ? "VOL --" : ("VOL " + Audio.volume + "%")

    onWheel: delta => Audio.step(delta > 0 ? 5 : -5)
    onRightClicked: Audio.toggleMute()

    // Auch per Tastenkuerzel aufklappbar -- nicht als Bindung, sonst
    // ueberschriebe sie den Klick auf die Zelle.
    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: Runtime.audioPanelOpen = root.popoutVisible

    Connections {
        target: Runtime

        function onAudioPanelOpenChanged() {
            root.setPopout(Runtime.audioPanelOpen);
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 40 * Theme.cellW

            spacing: Theme.cellH * 0.4

            Text {
                text: "AUDIO"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            // ── Ausgabe ───────────────────────────────────────────────────

            Text {
                width: panel.rowWidth
                text: Audio.label(Audio.sink)
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }

            Row {
                spacing: Theme.cellW

                LevelBar {
                    cells: 24
                    value: Audio.volume
                    maximum: Audio.maxVolume
                    fillColor: Audio.muted ? Theme.muted : Theme.accent
                    onMoved: v => Audio.setVolume(v)
                }

                Text {
                    // Feste Breite in Zeichen, damit der Balken beim Regeln
                    // nicht wandert.
                    text: (Audio.muted ? "stumm" : (Audio.volume + "%")).padStart(6, " ")
                    color: Audio.muted ? Theme.red : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }

            // ── Mikrofon ──────────────────────────────────────────────────

            Row {
                spacing: Theme.cellW
                visible: Audio.source?.audio !== undefined && Audio.source?.audio !== null

                LevelBar {
                    cells: 24
                    value: Audio.micVolume
                    interactive: false
                    fillColor: Audio.micMuted ? Theme.muted : Theme.green
                }

                Text {
                    text: (Audio.micMuted ? "stumm" : ("MIC " + Audio.micVolume + "%")).padStart(6, " ")
                    color: Audio.micMuted ? Theme.red : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.setMicMuted(!Audio.micMuted)
                    }
                }
            }

            // ── Geraete ───────────────────────────────────────────────────

            Text {
                text: "AUSGABE"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: Audio.sinks

                Rectangle {
                    id: device

                    required property var modelData

                    readonly property bool isCurrent: modelData === Audio.sink

                    width: panel.rowWidth
                    height: Theme.cellH * 1.4
                    radius: Theme.radius
                    color: mouse.containsMouse ? Theme.selection : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.cellW / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: (device.isCurrent ? "▸ " : "  ") + Audio.label(device.modelData)
                        color: device.isCurrent ? Theme.accent : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.setSink(device.modelData)
                    }
                }
            }
        }
    }
}
