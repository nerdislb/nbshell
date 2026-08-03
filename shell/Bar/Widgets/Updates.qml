import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Updates: Symbol und Anzahl in der Leiste, Liste im Popout.
//
// Ohne offene Updates bleibt die Zelle leer -- eine Null, die man taeglich
// liest, ist nur Rauschen. Klick prueft neu, Rechtsklick startet die
// Aktualisierung im Terminal.
//
// Das Symbol macht es wie DMS: waehrend der Pruefung dreht sich ein Pfeilkreis,
// sonst steht dort der Ablagekorb mit Pfeil und die Zahl daneben. Ein "UPD 12"
// las sich wie eine Abkuerzung, die man erst lernen muss.
Cell {
    id: root

    // Nerd-Font, dieselbe Quelle wie beim KI-Baustein.
    readonly property string glyphDownload: String.fromCodePoint(0xF01DA)
    readonly property string glyphRefresh: String.fromCodePoint(0xF0450)

    shown: Updates.enabled && (Updates.count > 0 || Updates.checking)
    custom: true
    interactive: true
    color: Updates.count >= 50 ? Theme.yellow : Theme.text

    onRightClicked: Updates.update()

    Row {
        spacing: Theme.cellW * 0.6

        // Die Kinder eines Positionierers duerfen selbst KEINE Anker haben --
        // sonst rechnet die Reihe mit Breite 0. Deshalb je ein Kaestchen auf
        // Zeilenhoehe, in dem das Zeichen dann mittig sitzen darf.
        Item {
            width: mark.implicitWidth
            height: Theme.cellH

            Glyph {
                id: mark

                anchors.centerIn: parent
                text: Updates.checking ? root.glyphRefresh : root.glyphDownload
                color: root.color

                // Dreht sich nur waehrend der Pruefung -- und steht danach
                // wieder gerade, statt schief stehen zu bleiben.
                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 1200
                    loops: Animation.Infinite
                    running: Updates.checking

                    onRunningChanged: if (!running)
                        mark.rotation = 0
                }
            }
        }

        Item {
            width: count.implicitWidth
            height: Theme.cellH
            visible: !Updates.checking

            Text {
                id: count

                anchors.centerIn: parent
                text: Updates.count
                color: root.color
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 44 * Theme.cellW

            spacing: Theme.cellH * 0.2

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 1.4

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "UPDATES  (" + Updates.count + ")" + (Updates.aur.length > 0 ? "  ·  davon " + Updates.aur.length + " AUR" : "")
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.cellW * 2

                    Text {
                        text: Updates.checking ? "[ prueft … ]" : "[ neu pruefen ]"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Updates.refresh()
                        }
                    }

                    Text {
                        visible: Updates.count > 0
                        text: "[ aktualisieren ]"
                        color: Theme.green
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Updates.update();
                                if (panel.closePopout)
                                    panel.closePopout();
                            }
                        }
                    }
                }
            }

            Text {
                visible: Updates.count === 0
                text: Updates.ready ? "alles aktuell" : "noch nicht geprueft"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: Updates.repo.concat(Updates.aur).slice(0, 18)

                delegate: Text {
                    required property var modelData

                    width: panel.rowWidth
                    text: "  " + modelData.name + "   " + modelData.from + " → " + modelData.to
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: Updates.count > 18
                text: "  … und " + (Updates.count - 18) + " weitere"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }
        }
    }
}
