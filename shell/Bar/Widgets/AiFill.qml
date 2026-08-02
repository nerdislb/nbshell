import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Verbrauchsanzeige als Symbol, das sich von unten fuellt -- uebernommen aus
// dem DMS-Plugin `aiFillWidget`, samt der Messung, die dort das Entscheidende
// war.
Cell {
    id: root

    readonly property var glyphs: ({
            "claude": String.fromCodePoint(0xF167A),
            "antigravity": String.fromCodePoint(0xF0674)
        })

    // Die gewuenschte Tintenhoehe. NICHT die Schriftgroesse: jedes Zeichen
    // bemalt einen anderen Anteil seiner Zeile, gleiche pixelSize ergibt also
    // verschieden grosse Symbole.
    readonly property real inkTarget: Math.round(Theme.cellH * 0.8)

    shown: AiUsage.available && AiUsage.list.length > 0
    custom: true
    interactive: true

    onClicked: AiUsage.refresh()

    Row {
        spacing: Theme.cellW

        Repeater {
            model: AiUsage.list

            Item {
                id: mark

                required property var modelData

                readonly property string glyph: root.glyphs[modelData.id] ?? String.fromCodePoint(0xF0674)

                // Fuellstand auf 5 % gerundet, damit er nicht bei jedem Abruf
                // um ein Pixel zappelt. 0 bleibt 0; alles darueber bekommt
                // eine Mindesthoehe, sonst ist bei 3 % nichts zu sehen.
                readonly property real fraction: {
                    const p = Math.max(0, Math.min(100, modelData.percent));
                    return p <= 0 ? 0 : Math.max(Math.round(p / 5) * 5 / 100, 0.22);
                }

                width: base.implicitWidth
                height: base.implicitHeight

                // Messung bei fester Groesse: daraus ergibt sich, welchen
                // Anteil seiner Zeile dieses Zeichen ueberhaupt bemalt. Die
                // Probe haengt NICHT an base.font, sonst drehte sich die
                // Rechnung im Kreis.
                TextMetrics {
                    id: probe
                    font.family: Theme.fontFamily
                    font.pixelSize: 100
                    text: mark.glyph
                }

                readonly property real inkRatio: Math.max(0.2, probe.tightBoundingRect.height / 100)

                Text {
                    id: base
                    text: mark.glyph
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(root.inkTarget / mark.inkRatio)
                    // QtRendering statt NativeRendering: die Zeichnung wird
                    // beschnitten, und nur so bleibt die Kante sauber.
                    renderType: Text.QtRendering
                    color: Theme.alpha(Theme.fg, 0.3)
                }

                TextMetrics {
                    id: metrics
                    font: base.font
                    text: base.text
                }

                // tightBoundingRect zaehlt ab der GRUNDLINIE (y ist negativ,
                // das Zeichen steht darueber), das Text-Element ab seiner
                // Oberkante. Dazwischen liegt die Oberlaenge -- die kommt aus
                // FontMetrics. `baselineOffset` taugt dafuer nicht, es ist 0.
                FontMetrics {
                    id: fm
                    font: base.font
                }

                readonly property real inkHeight: Math.max(1, metrics.tightBoundingRect.height)
                readonly property real inkBottom: fm.ascent + metrics.tightBoundingRect.y + metrics.tightBoundingRect.height

                property real fillHeight: mark.inkHeight * mark.fraction

                Behavior on fillHeight {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }

                Item {
                    id: fillClip

                    clip: true
                    x: base.x
                    y: mark.inkBottom - mark.fillHeight
                    width: base.width
                    height: mark.fillHeight

                    Text {
                        x: 0
                        y: base.y - fillClip.y
                        text: base.text
                        font: base.font
                        renderType: Text.QtRendering
                        color: mark.modelData.percent >= 90 ? Theme.red : Theme.accent
                    }
                }
            }
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 34 * Theme.cellW

            spacing: Theme.cellH * 0.3

            Text {
                text: "VERBRAUCH"
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Repeater {
                model: AiUsage.list

                Column {
                    id: entry

                    required property var modelData

                    width: panel.rowWidth
                    spacing: 0

                    Text {
                        text: entry.modelData.id + "   " + entry.modelData.percent + "%   " + entry.modelData.window + ", " + AiUsage.untilReset(entry.modelData)
                        color: entry.modelData.percent >= 90 ? Theme.red : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }

                    LevelBar {
                        cells: 30
                        value: entry.modelData.percent
                        interactive: false
                        fillColor: entry.modelData.percent >= 90 ? Theme.red : Theme.accent
                    }

                    Text {
                        visible: entry.modelData.secondary >= 0
                        text: "        " + entry.modelData.secondary + "%   " + entry.modelData.secondaryWindow + ", " + AiUsage.untilReset({
                                "resetsAt": entry.modelData.secondaryResetsAt
                            })
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }
                }
            }

            Text {
                text: "Klick auf das Symbol aktualisiert"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }
        }
    }
}
