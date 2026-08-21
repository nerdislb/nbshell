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

    preview: Component {
        BarPreview {
            icon: Updates.checking ? Icons.refresh : Icons.download
            title: "System updates"
            subtitle: Updates.checking ? "Checking repositories" : "Available packages"
            badge: Updates.checking ? "…" : String(Updates.count)
            badgeColor: Updates.rebootRecommended ? Theme.red : (Updates.count > 0 ? Theme.yellow : Theme.green)
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Repositories", "value": String(Updates.repo.length) },
                        { "label": "AUR", "value": String(Updates.aur.length) },
                        { "label": "Flatpak", "value": String(Updates.flatpak.length) },
                        { "label": "Restart", "value": Updates.rebootRecommended ? "recommended" : "not required", "color": Updates.rebootRecommended ? Theme.red : Theme.fg }
                    ]
                }
            ]
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 58 * Theme.cellW

            spacing: Theme.cellH * 0.2

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 2.6

                PanelHead {
                    anchors.left: parent.left
                    rowWidth: panel.rowWidth - actions.width - Theme.spaceLg
                    icon: Updates.checking ? Icons.refresh : Icons.download
                    title: "System updates"
                    subtitle: Updates.checking ? "Checking repositories" : "Available packages"
                    badge: String(Updates.count)
                }

                Row {
                    id: actions

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.cellW * 2

                    ActionButton {
                        text: Updates.checking ? "Checking …" : "Check again"
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
                        parts.push(Updates.repo.length + " repositories");
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
