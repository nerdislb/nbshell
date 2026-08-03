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
        spacing: Theme.cellW * 1.5

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

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: Theme.cellW * 46
            readonly property var d: SysInfo.detail

            spacing: Theme.cellH * 0.25

            component Heading: Text {
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                topPadding: Theme.cellH * 0.3
            }

            component Line: Text {
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            // Eine Zeile aus Beschriftung, Balken und Wert -- dreimal
            // dasselbe Raster, damit die Zahlen untereinander stehen.
            component Gauge: Item {
                id: gauge

                property string label: ""
                property int percent: 0
                property string value: ""
                property color fill: Theme.readable(Theme.accent, Theme.bg)

                width: panel.rowWidth
                height: Theme.cellH * 1.3

                Text {
                    id: gaugeLabel

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.cellW * 9
                    text: gauge.label
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
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

                Text {
                    anchors.left: gaugeBar.right
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    text: gauge.value
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }

            // ── Prozessor ─────────────────────────────────────────────────

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 1.2

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysInfo.hasDetail ? String(panel.d.modell) : "PROZESSOR"
                    color: Theme.readable(Theme.accent, Theme.bg)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }
            }

            Gauge {
                label: "CPU"
                percent: SysInfo.cpuPercent
                value: SysInfo.cpuPercent + " %" + (SysInfo.hasDetail && panel.d.mhz ? "   " + panel.d.mhz + " MHz" : "")
            }

            Line {
                visible: SysInfo.hasDetail
                text: "  Last " + (SysInfo.hasDetail ? panel.d.last.join("  ") : "") + "     Laufzeit " + (SysInfo.hasDetail ? SysInfo.uptimeText(panel.d.laufzeit) : "")
                color: Theme.fgDim
            }

            // Die Kerne als Balkenreihe. Ein Zeichen je Kern waere zu wenig,
            // eine Zeile je Kern zu viel -- zwoelf kurze Balken passen.
            Flow {
                visible: SysInfo.hasDetail
                width: panel.rowWidth
                spacing: Theme.cellW

                Repeater {
                    model: SysInfo.hasDetail ? (panel.d.kerne ?? []) : []

                    Row {
                        required property var modelData
                        required property int index

                        spacing: Theme.cellW * 0.5

                        Text {
                            text: String(parent.index).padStart(2, " ")
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
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

            Heading {
                text: "SPEICHER"
            }

            Gauge {
                label: "RAM"
                percent: SysInfo.memPercent
                value: SysInfo.memUsedGb.toFixed(1) + " / " + SysInfo.memTotalGb.toFixed(1) + " GB"
            }

            Gauge {
                visible: SysInfo.hasDetail && panel.d.speicher.swap_gesamt > 0
                label: "Swap"
                percent: SysInfo.hasDetail && panel.d.speicher.swap_gesamt > 0 ? Math.round(100 * panel.d.speicher.swap_benutzt / panel.d.speicher.swap_gesamt) : 0
                value: SysInfo.hasDetail ? (panel.d.speicher.swap_benutzt.toFixed(1) + " / " + panel.d.speicher.swap_gesamt.toFixed(1) + " GB") : ""
                fill: Theme.magenta
            }

            Line {
                visible: SysInfo.hasDetail
                text: "  davon Cache " + (SysInfo.hasDetail ? panel.d.speicher.cache.toFixed(1) : "0") + " GB"
                color: Theme.fgDim
            }

            Gauge {
                visible: SysInfo.hasDetail && panel.d.platte
                label: "Platte /"
                percent: SysInfo.hasDetail && panel.d.platte ? panel.d.platte.prozent : 0
                value: SysInfo.hasDetail && panel.d.platte ? (panel.d.platte.benutzt + " / " + panel.d.platte.gesamt + " GB") : ""
                fill: Theme.cyan
            }

            // ── Temperaturen ──────────────────────────────────────────────

            Heading {
                visible: SysInfo.hasDetail && (panel.d.temps ?? []).length > 0
                text: "TEMPERATUR"
            }

            Repeater {
                model: SysInfo.hasDetail ? (panel.d.temps ?? []) : []

                Item {
                    id: tempRow

                    required property var modelData

                    width: panel.rowWidth
                    height: Theme.cellH * 1.2

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.cellW * 16
                        text: tempRow.modelData.name
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW * 17
                        anchors.verticalCenter: parent.verticalCenter
                        text: tempRow.modelData.wert.toFixed(1) + " °C"
                        color: SysInfo.tempColor(tempRow.modelData.wert)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }
                }
            }

            // Luefter, die stehen, sind eine Aussage -- deshalb "aus" statt
            // gar keiner Zeile.
            Repeater {
                model: SysInfo.hasDetail ? (panel.d.luefter ?? []) : []

                Item {
                    id: fanRow

                    required property var modelData

                    width: panel.rowWidth
                    height: Theme.cellH * 1.2

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.cellW * 16
                        text: fanRow.modelData.name
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW * 17
                        anchors.verticalCenter: parent.verticalCenter
                        text: fanRow.modelData.wert > 0 ? (fanRow.modelData.wert + " U/min") : "aus"
                        color: fanRow.modelData.wert > 0 ? Theme.fg : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        renderType: Text.NativeRendering
                    }
                }
            }

            // ── Grafikkarte ───────────────────────────────────────────────

            Heading {
                visible: SysInfo.hasDetail && panel.d.gpu
                text: "GRAFIK"
            }

            Line {
                visible: SysInfo.hasDetail && panel.d.gpu
                text: SysInfo.hasDetail && panel.d.gpu ? ("  " + panel.d.gpu.name) : ""
                color: Theme.fgDim
                elide: Text.ElideRight
                width: panel.rowWidth
            }

            Item {
                visible: SysInfo.hasDetail && panel.d.gpu
                width: panel.rowWidth
                height: Theme.cellH * 1.2

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.cellW
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysInfo.hasDetail && panel.d.gpu ? (panel.d.gpu.last + " %   " + panel.d.gpu.benutzt + " / " + panel.d.gpu.gesamt + " MB") : ""
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysInfo.hasDetail && panel.d.gpu ? (panel.d.gpu.temp.toFixed(0) + " °C") : ""
                    color: SysInfo.hasDetail && panel.d.gpu ? SysInfo.tempColor(panel.d.gpu.temp) : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }

            Line {
                visible: !SysInfo.hasDetail
                text: "  wird gemessen …"
                color: Theme.muted
            }
        }
    }
}
