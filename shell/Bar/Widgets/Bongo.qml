import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Bar-Zugang fuer die frei stehende Bongo Cat. Links oeffnet die Einstellungen,
// rechts schaltet sie, das Mausrad skaliert und der Test sitzt im Popout.
Cell {
    id: root

    shown: true
    interactive: true
    icon: String.fromCodePoint(0xF011B) // nf-md-cat
    label: "CAT"
    color: BongoCat.active ? Theme.barAccent : Theme.textDim

    onRightClicked: BongoCat.toggle()
    onWheel: delta => BongoCat.setWidth(BongoCat.catWidth + (delta > 0 ? 20 : -20))

    popout: Component {
        Column {
            id: panel
            property var closePopout: null
            readonly property real rowWidth: 48 * Theme.cellW
            spacing: Theme.cellH * 0.3

            Item {
                width: panel.rowWidth; height: Theme.cellH * 4.5
                Image {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: Theme.cellW * 13; height: width * 360 / 864
                    source: BongoCat.frameSource; fillMode: Image.Stretch; smooth: true
                }
                Column {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.cellW * 15
                    Line { text: "BONGO CAT"; color: Theme.fgBright; font.pixelSize: Theme.fontSize + 4 }
                    Line { width: parent.width; text: BongoCat.statusText(); color: BongoCat.inputState === "ready" ? Theme.green : Theme.fgDim; elide: Text.ElideRight }
                }
            }

            Rule { rowWidth: panel.rowWidth; label: "CAT" }

            Segments {
                rowWidth: panel.rowWidth
                options: [
                    { "label": BongoCat.active ? "active" : "off", "value": "toggle" },
                    { "label": "Pfoten testen", "value": "test" },
                    { "label": "Reset", "value": "reset" }
                ]
                current: BongoCat.active ? "toggle" : ""
                onChosen: value => {
                    if (value === "toggle") BongoCat.toggle();
                    else if (value === "test") BongoCat.test();
                    else BongoCat.resetPosition();
                }
            }

            Facts {
                rowWidth: panel.rowWidth
                pairs: [
                    { "label": "Breite", "value": BongoCat.catWidth + " px" },
                    { "label": "Rechts", "value": BongoCat.rightMargin + " px" },
                    { "label": "Unten", "value": BongoCat.bottomMargin + " px" },
                    { "label": "Input", "value": BongoCat.keyboards }
                ]
            }

            Rule { rowWidth: panel.rowWidth; label: "SIZE AND POSITION" }
            Segments {
                rowWidth: panel.rowWidth
                options: [
                    { "label": "− kleiner", "value": "smaller" },
                    { "label": "+ groesser", "value": "larger" },
                    { "label": "←", "value": "left" },
                    { "label": "→", "value": "right" },
                    { "label": "↑", "value": "up" },
                    { "label": "↓", "value": "down" }
                ]
                current: ""
                onChosen: value => {
                    if (value === "smaller") BongoCat.setWidth(BongoCat.catWidth - 20);
                    else if (value === "larger") BongoCat.setWidth(BongoCat.catWidth + 20);
                    else if (value === "left") BongoCat.move(10, 0);
                    else if (value === "right") BongoCat.move(-10, 0);
                    else if (value === "up") BongoCat.move(0, 10);
                    else if (value === "down") BongoCat.move(0, -10);
                }
            }

            Rule { rowWidth: panel.rowWidth; label: "KEYBOARD INPUT  (SESSION)" }
            Line {
                width: panel.rowWidth; wrapMode: Text.Wrap
                text: "The helper only reports left/right paw. No keys or text leave /dev/input."
                color: Theme.muted
            }
            Segments {
                rowWidth: panel.rowWidth
                options: BongoCat.authorized
                    ? [{ "label": "Zugriff entziehen", "value": "revoke" }]
                    : [{ "label": "Input erlauben", "value": "allow" }]
                current: BongoCat.authorized ? "revoke" : ""
                onChosen: value => value === "allow" ? BongoCat.allowInput() : BongoCat.revokeInput()
            }
        }
    }
}
