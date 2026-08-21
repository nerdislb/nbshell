import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// CPU- und Speicherlast in einer Zelle. Die Zahlen sind auf zwei Stellen
// aufgefuellt, damit die Zelle beim Zaehlen nicht springt.
//
// Zwei Werte, zwei Symbole -- deshalb baut dieser Baustein seine Zeile selbst,
// statt das eine Symbol der Zelle zu benutzen. Ohne Symbole stehen wieder die
// Kuerzel davor, sonst waeren es zwei nackte Prozentzahlen nebeneinander.
//
// Ein Klick klappt die Einzelheiten auf: Kerne, Temperaturen, Luefter,
// Speicher, Platte. Die werden erst gemessen, solange das Popout offen ist --
// vorher waere es ein Skriptaufruf alle zwei Sekunden fuer nichts.
Cell {
    id: root

    function pad(n) {
        return (n < 10 ? " " : "") + n;
    }

    custom: true
    color: SysInfo.cpuPercent >= 90 ? Theme.red : Theme.text

    onPopoutVisibleChanged: SysInfo.detailWanted = root.popoutVisible

    Row {
        spacing: Theme.cellW * 0.65

        IconText {
            icon: Icons.cpu
            text: (Config.widgetIcons ? "" : "CPU ") + root.pad(SysInfo.cpuPercent) + "%"
            color: root.color
        }

        IconText {
            icon: Icons.memory
            text: (Config.widgetIcons ? "" : "RAM ") + root.pad(SysInfo.memPercent) + "%"
            color: Theme.text
        }
    }

    preview: Component {
        BarPreview {
            icon: Icons.cpu
            title: "System"
            subtitle: "Current load"
            badge: SysInfo.cpuPercent + "% CPU"
            badgeColor: SysInfo.cpuPercent >= 90 ? Theme.red : Theme.accent
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Processor", "value": SysInfo.cpuPercent + " %", "color": SysInfo.cpuPercent >= 90 ? Theme.red : Theme.fg },
                        { "label": "Memory", "value": SysInfo.memPercent + " %", "color": SysInfo.memPercent >= 90 ? Theme.red : Theme.fg }
                    ]
                },
                Line {
                    width: parent.width
                    text: "Click for temperatures, disks and processes"
                    color: Theme.muted
                    font.pixelSize: Theme.fontCaption
                }
            ]
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            // Zwei Zeichen mehr als frueher: die Balken sind seit der Korrektur an
            // LevelBar so breit, wie sie gemalt werden -- und damit ein Stueck
            // breiter als 20 Zellen. Ohne die zwei Zellen mehr rutschte das "GB"
            // der Plattenzeile aus dem Kasten.
            readonly property real rowWidth: Theme.cellW * 48
            readonly property var d: SysInfo.detail
            readonly property bool ready: panel.d?.ok === true && panel.d?.speicher !== undefined

            spacing: Theme.cellH * 0.25

            // Eine Zeile aus Beschriftung, Balken und Wert -- dreimal
            // dasselbe Raster, damit die Zahlen untereinander stehen.
            component Gauge: Item {
                id: gauge

                property string label: ""
                property int percent: 0
                property string value: ""
                property color fill: Theme.readable(Theme.accent, Theme.bg)

                width: panel.rowWidth
                height: Theme.controlHeight

                Line {
                    id: gaugeLabel

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.cellW * 9
                    text: gauge.label
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontCaption
                    // Neun Zeichen sind das, was die Zeile hergibt: dahinter
                    // stehen 20 Balkenzellen und die Zahlen, und die Zeile ist
                    // 48 Zeichen breit. Ein langer Einhaengepunkt schiebt sonst
                    // die Zahlen aus dem Kasten.
                    elide: Text.ElideRight
                }

                LevelBar {
                    id: gaugeBar

                    anchors.left: gaugeLabel.right
                    anchors.verticalCenter: parent.verticalCenter
                    cells: 20
                    value: gauge.percent
                    fillColor: gauge.fill
                    interactive: false
                }

                Line {
                    anchors.left: gaugeBar.right
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    text: gauge.value
                    color: Theme.fg
                    font.pixelSize: Theme.fontBody
                }
            }

            // ── Prozessor ─────────────────────────────────────────────────

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Icons.cpu
                title: panel.ready ? String(panel.d.modell ?? "Processor") : "Processor"
                subtitle: panel.ready && panel.d.mhz ? (panel.d.mhz + " MHz") : ""
                badge: SysInfo.cpuPercent + " %"
                badgeColor: SysInfo.cpuPercent >= 90 ? Theme.red : Theme.fgDim
            }

            Gauge {
                label: "CPU"
                percent: SysInfo.cpuPercent
                value: SysInfo.cpuPercent + " %" + (panel.ready && panel.d.mhz ? "   " + panel.d.mhz + " MHz" : "")
            }

            Facts {
                visible: panel.ready
                rowWidth: panel.rowWidth
                pairs: panel.ready ? [
                    {
                        "label": "Load",
                        "value": (panel.d.last ?? []).join("  ")
                    },
                    {
                        "label": "Uptime",
                        "value": SysInfo.uptimeText(panel.d.laufzeit)
                    }
                ] : []
            }

            // Die Kerne als Balkenreihe. Ein Zeichen je Kern waere zu wenig,
            // eine Zeile je Kern zu viel -- zwoelf kurze Balken passen.
            Flow {
                visible: panel.ready
                width: panel.rowWidth
                spacing: Theme.cellW

                Repeater {
                    model: panel.ready ? (panel.d.kerne ?? []) : []

                    Row {
                        required property var modelData
                        required property int index

                        spacing: Theme.cellW * 0.5

                        Line {
                            text: String(parent.index).padStart(2, " ")
                            color: Theme.muted
                        }

                        LevelBar {
                            cells: 5
                            value: parent.modelData
                            fillColor: parent.modelData >= 90 ? Theme.red : Theme.readable(Theme.accent, Theme.bg)
                            interactive: false
                        }
                    }
                }
            }

            // ── Speicher ──────────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                label: "MEMORY"
            }

            Gauge {
                label: "RAM"
                percent: SysInfo.memPercent
                value: SysInfo.memUsedGb.toFixed(1) + " / " + SysInfo.memTotalGb.toFixed(1) + " GB"
            }

            Gauge {
                visible: panel.ready && (panel.d.speicher?.swap_gesamt ?? 0) > 0
                label: "Swap"
                percent: panel.ready && panel.d.speicher.swap_gesamt > 0 ? Math.round(100 * panel.d.speicher.swap_benutzt / panel.d.speicher.swap_gesamt) : 0
                value: panel.ready ? (panel.d.speicher.swap_benutzt.toFixed(1) + " / " + panel.d.speicher.swap_gesamt.toFixed(1) + " GB") : ""
                fill: Theme.magenta
            }

            Line {
                visible: panel.ready
                text: "  cache " + (panel.ready ? panel.d.speicher.cache.toFixed(1) : "0") + " GB"
                color: Theme.fgDim
            }

            // Alle Datentraeger, nicht nur die Wurzel -- der Gedanke ist von
            // omarchy-diskspace. Untervolumen desselben Traegers fasst das
            // Skript schon zusammen; hier steht nur noch, was uebrig bleibt:
            // die Platte, /boot, und was gerade im Kartenleser steckt.
            //
            // Ab 90 % wird der Balken rot. Das ist die Warnung, wegen der man
            // so eine Liste ueberhaupt aufmacht.
            Repeater {
                model: panel.ready ? (panel.d.platten ?? []) : []

                delegate: Gauge {
                    required property var modelData

                    // Neun Zeichen Platz: kurze Pfade ganz, lange nur mit dem
                    // letzten Stueck -- "/run/media/nerdi/NIKON D750" sagt als
                    // "NIKON D7…" mehr als als "/run/med…".
                    label: modelData.ort.length <= 9 ? modelData.ort : modelData.ort.split("/").filter(t => t !== "").pop()
                    percent: modelData.prozent
                    value: modelData.benutzt + " / " + modelData.gesamt + " GB"
                    fill: modelData.prozent >= 90 ? Theme.red : Theme.cyan
                }
            }

            // Faellt die Liste aus (alte Antwort im Zwischenspeicher), bleibt
            // wenigstens die Wurzel stehen.
            Gauge {
                visible: panel.ready && !!panel.d.platte && (panel.d.platten ?? []).length === 0
                label: "/"
                percent: panel.ready && panel.d.platte ? panel.d.platte.prozent : 0
                value: panel.ready && panel.d.platte ? (panel.d.platte.benutzt + " / " + panel.d.platte.gesamt + " GB") : ""
                fill: Theme.cyan
            }

            // ── Temperaturen ──────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                visible: panel.ready && ((panel.d.temps ?? []).length > 0 || (panel.d.luefter ?? []).length > 0)
                label: "TEMPERATURE AND FANS"
            }

            // Temperaturen und Luefter zusammen in EINEM Raster: es sind
            // dieselbe Art Angabe -- ein Name und eine Zahl --, und sie
            // wechselten sich vorher in zwei fast gleichen Bloecken ab. Ein
            // stehender Luefter bleibt dabei stehen: "aus" ist eine Aussage,
            // eine fehlende Zeile waere keine.
            Facts {
                rowWidth: panel.rowWidth
                pairs: {
                    if (!panel.ready)
                        return [];
                    const temps = (panel.d.temps ?? []).map(t => ({
                                "label": t.name,
                                "value": t.wert.toFixed(1) + " °C",
                                "color": SysInfo.tempColor(t.wert)
                            }));
                    const fans = (panel.d.luefter ?? []).map(f => ({
                                "label": f.name,
                                "value": f.wert > 0 ? (f.wert + " RPM") : "off",
                                "color": f.wert > 0 ? Theme.fg : Theme.muted
                            }));
                    return temps.concat(fans);
                }
            }

            // ── Grafikkarte ───────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                visible: panel.ready && !!panel.d.gpu
                label: "GRAPHICS"
            }

            PanelHead {
                rowWidth: panel.rowWidth
                visible: panel.ready && !!panel.d.gpu
                title: panel.ready && panel.d.gpu ? String(panel.d.gpu.name) : ""
                badge: panel.ready && panel.d.gpu ? (panel.d.gpu.temp.toFixed(0) + " °C") : ""
                badgeColor: panel.ready && panel.d.gpu ? SysInfo.tempColor(panel.d.gpu.temp) : Theme.fgDim
            }

            Facts {
                rowWidth: panel.rowWidth
                visible: panel.ready && !!panel.d.gpu
                pairs: panel.ready && panel.d.gpu ? [
                    {
                        "label": "Load",
                        "value": panel.d.gpu.last + " %"
                    },
                    {
                        "label": "Memory",
                        "value": panel.d.gpu.benutzt + " / " + panel.d.gpu.gesamt + " MB"
                    }
                ] : []
            }

            Line {
                visible: !panel.ready
                text: "  measuring …"
                color: Theme.muted
            }
        }
    }
}
