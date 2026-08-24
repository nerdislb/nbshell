import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Etwas ans Telefon geben, ohne eine App zu starten.
//
// Klick oeffnet die Liste; gescanning wird erst dann. Je Geraet zwei Knoepfe:
// die Clipboard und das letzte Bildschirmfoto -- das sind die beiden
// Dinge, die man tatsaechlich schnell hinueberschieben will. Alles andere geht
// ueber `nbshell nearby send <datei>`, weil ein Dateiwaehler in einer Leiste
// zwei Bedienungen zu viel waere.
Cell {
    id: root

    shown: Nearby.enabled
    quiet: Nearby.devices.length === 0 && !Nearby.sending
    interactive: true
    slotChars: 2

    label: "SEND"
    icon: Icons.share
    text: Nearby.devices.length > 0 ? String(Nearby.devices.length) : ""
    color: Nearby.sending ? Theme.yellow : (Nearby.devices.length > 0 ? Theme.text : Theme.textDim)

    // Nur suchen, solange jemand hinsieht.
    onPopoutVisibleChanged: Nearby.wanted = root.popoutVisible

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 46 * Theme.cellW

            spacing: Theme.cellH * 0.2

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.share
                title: "Nearby"
                subtitle: "LocalSend"
                badge: Nearby.scanning ? "scanning" : String(Nearby.devices.length)
            }

            Line {
                width: panel.rowWidth
                visible: Nearby.devices.length === 0
                text: Nearby.scanning ? "  scanning …" : "  no devices — LocalSend must be open on the other device"
                color: Theme.muted
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: Nearby.devices

                Column {
                    id: eintrag

                    required property var modelData

                    spacing: 0

                    Item {
                        width: panel.rowWidth
                        height: Theme.denseRowHeight

                        Line {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: eintrag.modelData.alias
                            color: Theme.fg
                        }

                        Line {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: eintrag.modelData.model + "  " + eintrag.modelData.ip
                            color: Theme.muted
                        }
                    }

                    Row {
                        spacing: Theme.cellW * 2

                        component Knopf: ActionButton {
                            compact: true
                        }

                        Knopf {
                            text: "Clipboard"
                            onTriggered: Nearby.sendText(eintrag.modelData, Clipboard.entries.length > 0 ? Clipboard.entries[0] : "")
                        }

                        Knopf {
                            text: "Latest image"
                            onTriggered: Nearby.sendLastShot(eintrag.modelData)
                        }
                    }
                }
            }

            Rule {
                rowWidth: panel.rowWidth
                visible: Nearby.status !== ""
            }

            Line {
                width: panel.rowWidth
                visible: Nearby.status !== ""
                text: "  " + Nearby.status
                color: Nearby.status.indexOf("failed") === 0 ? Theme.red : Theme.green
                wrapMode: Text.WordWrap
            }

            Line {
                width: panel.rowWidth
                text: "  Files: nbshell nearby send <file>"
                color: Theme.muted
                topPadding: Theme.cellH * 0.3
            }
        }
    }
}
