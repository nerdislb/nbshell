import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Kaputte Dienste. Unsichtbar, solange alles laeuft.
//
// Das ist der ganze Baustein: er meldet sich nur, wenn systemd eine Einheit
// aufgegeben hat -- und dann steht er da, wo sonst nichts war, und ist genau
// deshalb nicht zu uebersehen. Eine Zelle, die dauerhaft "0 Fehler" anzeigt,
// liest nach drei Tagen niemand mehr.
//
// Im Popout steht je Einheit, was sie ist und was mit ihr geschehen soll:
// neu starten, ins Protokoll sehen, oder den Vermerk wegraeumen.
Cell {
    id: root

    shown: Units.enabled && Units.count > 0
    interactive: true
    slotChars: 2

    icon: Icons.alert
    text: String(Units.count)
    color: Theme.red

    // Beim Aufklappen frisch nachsehen: zwischen zwei Abfragen liegen fuenf
    // Minuten, und wer hier klickt, will den Stand von jetzt.
    onPopoutVisibleChanged: if (root.popoutVisible)
        Units.refresh()

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 62 * Theme.cellW

            spacing: Theme.cellH * 0.2

            component Action: ActionButton {
                property color ton: Theme.fgDim
                tone: "primary"
                accentColor: ton
                compact: true
            }

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 1.4

                Line {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "FAILED  (" + Units.count + ")"
                    color: Theme.fgDim
                }

                Action {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Units.checking ? "Checking …" : "Check again"
                    busy: Units.checking
                    onTriggered: Units.refresh()
                }
            }

            Repeater {
                model: Units.failed.slice(0, 8)

                delegate: Column {
                    id: eintrag

                    required property var modelData

                    spacing: 0

                    Line {
                        width: panel.rowWidth
                        // Der Bereich gehoert an den Namen: `nbshell.service`
                        // gibt es als useren Dienst und als Systemdienst, und
                        // welcher gemeint ist, entscheidet, was die Knoepfe
                        // darunter tun.
                        text: "  " + eintrag.modelData.name + (eintrag.modelData.bereich === "user" ? "   (user)" : "   (System)")
                        color: Theme.fg
                        elide: Text.ElideRight
                    }

                    Line {
                        visible: eintrag.modelData.text !== ""
                        width: panel.rowWidth
                        text: "    " + eintrag.modelData.text
                        color: Theme.muted
                        elide: Text.ElideRight
                    }

                    Row {
                        leftPadding: Theme.cellW * 4
                        spacing: Theme.cellW * 2
                        bottomPadding: Theme.cellH * 0.3

                        Action {
                            text: "Restart"
                            ton: Theme.green
                            onTriggered: {
                                Units.restart(eintrag.modelData);
                                if (eintrag.modelData.bereich !== "user" && panel.closePopout)
                                    panel.closePopout();
                            }
                        }

                        Action {
                            text: "Journal"
                            onTriggered: {
                                Units.journal(eintrag.modelData);
                                if (panel.closePopout)
                                    panel.closePopout();
                            }
                        }

                        Action {
                            text: "Clear"
                            ton: Theme.red
                            onTriggered: {
                                Units.clear(eintrag.modelData);
                                if (eintrag.modelData.bereich !== "user" && panel.closePopout)
                                    panel.closePopout();
                            }
                        }
                    }
                }
            }

            Line {
                visible: Units.count > 8
                text: "  … and " + (Units.count - 8) + " more"
                color: Theme.muted
            }

            // Systemeinheiten brauchen ein Passwort. Das steht hier, damit
            // niemand auf einen Knopf drueckt und sich wundert, warum ein
            // Terminal aufgeht.
            Line {
                visible: Units.systemUnits.length > 0
                text: "  System services ask for your password in the terminal."
                color: Theme.muted
                topPadding: Theme.cellH * 0.3
            }
        }
    }
}
