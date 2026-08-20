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
            "codex": String.fromCodePoint(0xF0169),
            "claude": String.fromCodePoint(0xF167A),
            "antigravity": String.fromCodePoint(0xF0674),
            "agy": String.fromCodePoint(0xF0674)
        })

    // Die gewuenschte Tintenhoehe. NICHT die Schriftgroesse: jedes Zeichen
    // bemalt einen anderen Anteil seiner Zeile, gleiche pixelSize ergibt also
    // verschieden grosse Symbole.
    readonly property real inkTarget: Math.round(Theme.cellH * 0.8)

    shown: Dictation.active || Agents.workingCount > 0 || Agents.waitingCount > 0
        || (AiUsage.available && AiUsage.list.length > 0)
    custom: true
    interactive: true

    onClicked: AiUsage.refresh()
    onRightClicked: Runtime.agentCenterOpen = true

    Row {
        id: statusRow

        height: root.height
        spacing: Theme.cellW

        Line {
            visible: Agents.workingCount > 0 || Agents.waitingCount > 0
            y: Math.round((statusRow.height - height) / 2)
            text: Icons.agent + "  " + (Agents.waitingCount > 0 ? (Agents.waitingCount + " WAIT") : (Agents.workingCount + " RUN"))
            color: Agents.waitingCount > 0 ? Theme.yellow : Theme.green
            TapHandler { onTapped: Runtime.agentCenterOpen = true }
        }

        Line {
            visible: Dictation.active
            y: Math.round((statusRow.height - height) / 2)
            text: String.fromCodePoint(0xF036C) + "  " + Dictation.label
            color: Dictation.state === "recording" ? Theme.red : Theme.yellow
            TapHandler { onTapped: Dictation.toggle() }
        }

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
                y: Math.round((statusRow.height - height) / 2)

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

            // 46 statt 34 Zeichen: seit Antigravity dazukam, stehen dort
            // Modellgruppen ("Claude & OpenAI Models") statt kurzer Fenster
            // ("5 hour") -- bei 34 brach schon die erste Zeile ab.
            readonly property real rowWidth: 46 * Theme.cellW

            spacing: Theme.cellH * 0.3

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.agent
                title: "AI usage"
                subtitle: "Model limits and active agents"
                badge: String(AiUsage.list.length)
            }

            Repeater {
                model: AiUsage.list

                Column {
                    id: entry

                    required property var modelData

                    width: panel.rowWidth
                    spacing: 0

                    Line {
                        width: panel.rowWidth
                        elide: Text.ElideRight
                        text: {
                            const time = AiUsage.untilReset(entry.modelData);
                            var s = entry.modelData.id + "   " + entry.modelData.percent + "%";
                            if (entry.modelData.window !== "")
                                s += "   " + entry.modelData.window;
                            if (time !== "")
                                s += (entry.modelData.window !== "" ? ", " : "   ") + time;
                            return s;
                        }
                        color: entry.modelData.percent >= 90 ? Theme.red : Theme.fg
                    }

                    LevelBar {
                        cells: 30
                        value: entry.modelData.percent
                        interactive: false
                        fillColor: entry.modelData.percent >= 90 ? Theme.red : Theme.accent
                    }

                    // Die weiteren Toepfe desselben Anbieters. Codex und Claude
                    // koennen weitere Zeitfenster haben, Antigravity Modellgruppen.
                    Repeater {
                        model: entry.modelData.more ?? []

                        Line {
                            required property var modelData

                            width: panel.rowWidth
                            elide: Text.ElideRight
                            text: {
                                const time = AiUsage.untilReset(modelData);
                                var s = "        " + modelData.percent + "%";
                                if (modelData.label !== "")
                                    s += "   " + modelData.label;
                                if (time !== "")
                                    s += (modelData.label !== "" ? ", " : "   ") + time;
                                return s;
                            }
                            color: modelData.percent >= 90 ? Theme.red : Theme.fgDim
                        }
                    }
                }
            }

            Line {
                text: "Click refreshes · right click opens Agent Center"
                color: Theme.muted
            }
        }
    }
}
