import QtQuick
import qs.Common

// Wie ein Theme aussieht, bevor man es nimmt: eine Miniatur der EIGENEN
// Leiste, in den Farben des Kandidaten gezeichnet, darunter seine Palette.
//
// Omarchy 4 loest dasselbe mit einem Karussell aus vorgerenderten
// Desktop-Screenshots -- pro Theme ein Bild, das jemand aufnehmen und
// mitliefern muss. Unsere 22 Themes bringen nur ihre `colors.toml` mit, und
// das ist gut so (84 KB statt 91 MB, siehe oben). Hier wird deshalb nichts
// geladen und nichts zwischengespeichert, sondern gezeichnet: alles, was die
// Miniatur braucht, sind zwoelf Farbwerte, die ohnehin schon in der Themeliste
// stehen.
//
// Und sie zeigt das Richtige. Ein fremder Desktop beantwortet die Frage "wie
// sieht das aus" mit einem Bild von jemand anderes Bildschirm; die Miniatur
// beantwortet sie mit der Leiste, die man gleich vor sich hat -- mit den
// eigenen Arbeitsflaechen, der eigenen Uhr, dem eigenen Akku.
//
// Gezeichnet wird mit ECHTEM Text in der echten Schrift, nur schmaler: eine
// Reihe abstrakter Bloecke waere huebscher und saehe nach jedem Theme gleich
// aus. Wie sich Vorder- auf Hintergrund liest, sieht man erst an Buchstaben.
Column {
    id: root

    // Ein Eintrag aus `ThemeIndex.list`.
    property var theme: null

    property real rowWidth: 0

    // Was fehlt, faellt auf etwas zurueck, das es sicher gibt. Ein leerer
    // Farbwert ist in QML durchsichtig -- die Miniatur haette dann Loecher,
    // durch die das AKTUELLE Theme durchscheint, und genau das waere die
    // irrefuehrendste aller Vorschauen.
    function tint(key, fallback) {
        const v = root.theme ? root.theme[key] : "";
        return (v && String(v).length > 0) ? v : fallback;
    }

    readonly property color bg: tint("background", "#000000")
    readonly property color fg: tint("foreground", "#ffffff")
    readonly property color dim: tint("dimForeground", root.fg)
    readonly property color bright: tint("brightForeground", root.fg)
    readonly property color line: tint("muted", root.dim)
    readonly property color accent: tint("accent", root.fg)

    visible: root.theme !== null
    spacing: Theme.cellH * 0.4

    // ── Die Leiste ───────────────────────────────────────────────────────
    Rectangle {
        id: mini

        width: root.rowWidth
        height: Theme.cellH * 1.9

        color: root.bg
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: root.line

        // Dieselbe Aufteilung wie die echte Leiste: links die
        // Arbeitsflaechen, in der Mitte die Uhr, rechts der Zustand.
        // Kein `anchors` in der Komponente: die meisten dieser Texte sitzen
        // in einer `Row`, und ein Kind eines Positionierers darf sich nicht
        // selbst verankern -- die Row richtet sie aus.
        component Mini: Line {}

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.cellW
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.cellW * 0.6

            Mini {
                text: "●"
                color: root.accent
            }

            Mini {
                text: "·"
                color: root.line
            }

            Mini {
                text: "·"
                color: root.line
            }

            // Kein Fenstertitel: bei 34 Zeichen Breite stiess er in der Mitte
            // auf die Uhr, und "nbshell12:34" ist keine Vorschau, sondern ein
            // Fehler. Die gedaempfte Schrift zeigt stattdessen der Punkt.
        }

        Mini {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "12:34"
            color: root.bright
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: Theme.cellW
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.cellW

            Mini {
                text: "42%"
                color: root.fg
            }

            Mini {
                text: "100%"
                color: root.tint("green", root.fg)
            }
        }
    }

    // ── Die Palette ──────────────────────────────────────────────────────
    // Acht Felder, lueckenlos aneinander -- so, wie ein Terminal seine
    // Farbtafel zeigt. Der Rahmen laeuft aussen herum und nicht um jedes
    // Feld: sonst zerfaellt die Reihe in acht Kaestchen und man vergleicht
    // die Abstaende statt der Farben.
    Rectangle {
        width: root.rowWidth
        height: Theme.cellH * 0.9
        color: "transparent"
        border.width: Theme.borderWidth
        border.color: root.line

        Row {
            anchors.fill: parent
            anchors.margins: Theme.borderWidth

            Repeater {
                model: [root.tint("red", root.fg), root.tint("yellow", root.fg), root.tint("green", root.fg), root.tint("cyan", root.fg), root.tint("blue", root.fg), root.tint("magenta", root.fg), root.accent, root.fg]

                Rectangle {
                    required property var modelData

                    width: (root.rowWidth - Theme.borderWidth * 2) / 8
                    height: parent.height
                    color: modelData
                }
            }
        }
    }
}
