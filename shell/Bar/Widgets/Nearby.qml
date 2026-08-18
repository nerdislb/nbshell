import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Etwas ans Telefon geben, ohne eine App zu starten.
//
// Klick oeffnet die Liste; gesucht wird erst dann. Je Geraet zwei Knoepfe:
// die Zwischenablage und das letzte Bildschirmfoto -- das sind die beiden
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
                title: "In der Naehe"
                subtitle: "LocalSend"
                badge: Nearby.scanning ? "sucht" : String(Nearby.devices.length)
            }

            Line {
                width: panel.rowWidth
                visible: Nearby.devices.length === 0
                text: Nearby.scanning ? "  sucht …" : "  niemand da — die Gegenstelle muss LocalSend offen haben"
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
                        height: Theme.cellH * 1.4

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
                            text: "Zwischenablage"
                            onTriggered: Nearby.sendText(eintrag.modelData, Clipboard.entries.length > 0 ? Clipboard.entries[0] : "")
                        }

                        Knopf {
                            text: "Letztes Bild"
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
                color: Nearby.status.indexOf("ging nicht") === 0 ? Theme.red : Theme.green
                wrapMode: Text.WordWrap
            }

            Line {
                width: panel.rowWidth
                text: "  Dateien: nbshell nearby send <datei>"
                color: Theme.muted
                topPadding: Theme.cellH * 0.3
            }
        }
    }
}
