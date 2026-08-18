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
// sonst steht dort der Pfeil nach unten und die Zahl daneben.
Cell {
    id: root

    shown: Updates.enabled && (Updates.count > 0 || Updates.checking)
    interactive: true
    slotChars: 3

    label: "UPD"
    icon: Updates.checking ? Icons.refresh : Icons.download
    iconSpins: Updates.checking
    // Waehrend der Pruefung waere die Zahl die alte -- besser gar keine.
    text: Updates.checking ? "" : String(Updates.count)
    color: Updates.count >= 50 ? Theme.yellow : Theme.text

    onRightClicked: Updates.update()

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 58 * Theme.cellW

            spacing: Theme.cellH * 0.2

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 1.4

                Line {
                    anchors.left: parent.left
                    anchors.right: actions.left
                    anchors.rightMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    // Keine Marke rechts wie in den anderen Popouts: dort
                    // stehen hier schon die Knoepfe (Pruefen, Update),
                    // und zwei Dinge am selben Rand sind eines zu viel.
                    text: "UPDATES  (" + Updates.count + ")"
                    color: Theme.fgDim
                }

                Row {
                    id: actions

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.cellW * 2

                    ActionButton {
                        text: Updates.checking ? "Prueft …" : "Check again"
                        busy: Updates.checking
                        compact: true
                        onTriggered: Updates.refresh()
                    }

                    ActionButton {
                        visible: Updates.count > 0
                        text: "Update"
                        tone: "primary"
                        accentColor: Theme.green
                        compact: true
                        onTriggered: {
                            Updates.update();
                            if (panel.closePopout)
                                panel.closePopout();
                        }
                    }
                }
            }

            Line {
                visible: Updates.count === 0
                text: Updates.ready ? "everything is up to date" : "not checked yet"
                color: Theme.muted
            }

            Repeater {
                model: Updates.repo.concat(Updates.aur).concat(Updates.flatpak).slice(0, 18)

                delegate: Line {
                    required property var modelData

                    width: panel.rowWidth
                    // Bei Flatpaks stehen oft zwei gleiche Versionen da: eine
                    // neue Fassung muss die Versionsnummer nicht aendern, das
                    // Paket ist trotzdem ein anderes. "v1.6.0 → v1.6.0" saehe
                    // aus wie ein Fehler.
                    text: modelData.from === modelData.to ? ("  " + modelData.name + "   " + modelData.to + "  (new build)") : ("  " + modelData.name + "   " + modelData.from + " → " + modelData.to)
                    color: Theme.fg
                    elide: Text.ElideRight
                }
            }

            // Woher sie kommen, steht UNTER der Liste: oben teilt sich die
            // Zeile den Platz mit zwei Knoepfen, und die Aufschluesselung
            // verlor ihn.
            Line {
                visible: Updates.aur.length > 0 || Updates.flatpak.length > 0
                text: {
                    const parts = [];
                    if (Updates.repo.length > 0)
                        parts.push(Updates.repo.length + " aus den Repos");
                    if (Updates.aur.length > 0)
                        parts.push(Updates.aur.length + " AUR");
                    if (Updates.flatpak.length > 0)
                        parts.push(Updates.flatpak.length + " Flatpak");
                    return "  " + parts.join(" · ");
                }
                color: Theme.muted
                topPadding: Theme.cellH * 0.3
            }

            Line {
                visible: Updates.count > 18
                text: "  … and " + (Updates.count - 18) + " more"
                color: Theme.muted
            }
        }
    }
}
