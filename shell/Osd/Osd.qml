import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Die Einblendung selbst. Ein Fenster je Bildschirm -- welcher gerade
// angeschaut wird, weiss die Shell nicht, und auf dem falschen zu erscheinen
// waere aergerlicher als auf beiden.
//
// `mask: Region {}` macht das Fenster vollstaendig klickdurchlaessig: es soll
// nur zeigen, nie im Weg sein.
Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: win

        required property var modelData

        // In der Pille zeigt die Leiste die Einblendung selbst -- dann waere
        // dieses Fenster die zweite Anzeige desselben Werts, gleichzeitig, an
        // zwei Bildschirmraendern.
        readonly property bool takenByPill: Config.osdInPill && Config.mode === "pill"

        screen: modelData
        visible: Osd.showing && !takenByPill
        color: "transparent"

        WlrLayershell.namespace: "nbshell:osd"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        // Immer gegenueber der Leiste: steht die Insel unten, blendet die
        // Anzeige oben ein und umgekehrt. Sonst legen sich die beiden
        // uebereinander.
        anchors.left: true
        anchors.right: true
        anchors.top: Config.edge === "bottom"
        anchors.bottom: Config.edge !== "bottom"

        implicitHeight: Theme.cellH * 8

        mask: Region {}

        Rectangle {
            id: box

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: Config.edge === "bottom" ? parent.top : undefined
            anchors.bottom: Config.edge === "bottom" ? undefined : parent.bottom
            anchors.margins: Theme.cellH * 2

            width: content.implicitWidth + Theme.cellW * 4
            height: content.implicitHeight + Theme.cellH

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: Theme.muted

            // Kurz da, kurz weg -- ohne Bewegung wirkt es wie ein Fehler.
            opacity: Osd.showing ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }

            // Kinder eines Positionierers duerfen KEINE anchors haben -- mit
            // ihnen meldet die Reihe Breite 0, der Kasten schrumpft auf nichts
            // und die Einblendung bleibt unsichtbar, obwohl das Fenster da ist.
            // Alle drei Teile sind ohnehin eine Zeile hoch.
            Row {
                id: content

                anchors.centerIn: parent
                spacing: Theme.cellW * 2

                Text {
                    text: Osd.label
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                LevelBar {
                    cells: 24
                    value: Osd.value
                    interactive: false
                    fillColor: Osd.muted ? Theme.muted : Osd.tint
                }

                Text {
                    // Feste Breite in Zeichen, damit der Kasten beim Regeln
                    // nicht atmet.
                    text: (Osd.muted ? "stumm" : (Osd.value + "%")).padStart(6, " ")
                    color: Osd.muted ? Theme.red : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
