import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Updates: Anzahl in der Leiste, Liste im Popout.
//
// Ohne offene Updates bleibt die Zelle leer -- eine Null, die man taeglich
// liest, ist nur Rauschen. Klick prueft neu, Rechtsklick startet die
// Aktualisierung im Terminal.
Cell {
    id: root

    shown: Updates.enabled && (Updates.count > 0 || Updates.checking)
    interactive: true
    text: Updates.checking ? "UPD …" : ("UPD " + Updates.count)
    color: Updates.count >= 50 ? Theme.yellow : Theme.text

    onRightClicked: Updates.update()

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
