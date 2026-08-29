import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Lautstaerke. Mausrad regelt, Rechtsklick schaltet muted, Klick klappt die
// Regler und die Geraeteliste auf.
Cell {
    id: root

    shown: Audio.ready
    slotChars: 5
    interactive: true
    popoutTakesKeyboard: true
    color: Audio.muted ? Theme.red : Theme.text

    // Der Lautsprecher zeigt schon, worum es geht -- das "VOL" davor war
    // Beschriftung fuer eine Beschriftung.
    label: "VOL"
    icon: Audio.muted ? Icons.volumeMuted : (Audio.volume >= 67 ? Icons.volumeHigh : (Audio.volume >= 34 ? Icons.volumeMid : Icons.volumeLow))
    text: Audio.muted ? "--" : (Audio.volume + "%")

    // Die Schrittweite haengt daran, WIE gescrollt wurde: ein Mausrad rastet
    // und meldet 120 pro Rastung -- das sind die vollen 5 %. Ein Touchpad
    // meldet dagegen ein Dutzend kleiner Werte je Fingerbewegung; mit festen
    // 5 % waere die Lautstaerke bei der kleinsten Geste am Anschlag. Ein
    // Prozent ist die Untergrenze, sonst passierte gar nichts mehr.
    onWheel: delta => {
        const step = Math.max(1, Math.round(Math.abs(delta) / 120 * 5));
        Audio.step(delta > 0 ? step : -step);
    }
    onRightClicked: Audio.toggleMute()

    preview: Component {
        BarPreview {
            icon: Audio.muted ? Icons.volumeMuted : Icons.volumeHigh
            title: Audio.label(Audio.sink)
            subtitle: "Audio output"
            badge: Audio.muted ? "MUTED" : Audio.volume + " %"
            badgeColor: Audio.muted ? Theme.red : Theme.accent
            content: [
                LevelBar {
                    cells: 32
                    value: Audio.volume
                    maximum: Audio.maxVolume
                    fillColor: Audio.muted ? Theme.muted : Theme.accent
                    onMoved: value => Audio.setVolume(value)
                },
                Facts {
                    rowWidth: parent.width
                    pairs: [
                        { "label": "Playing apps", "value": String(Audio.appStreams.length) },
                        { "label": "Microphone", "value": Audio.micMuted ? "muted" : Audio.micVolume + " %", "color": Audio.micMuted ? Theme.red : Theme.fg }
                    ]
                }
            ]
        }
    }

    // Auch per Tastenkuerzel aufklappbar -- nicht als Bindung, sonst
    // ueberschriebe sie den Klick auf die Zelle.
    // Zurueckmelden, wenn der Kompositor das Popout geschlossen hat.
    onPopoutVisibleChanged: {
        Runtime.audioPanelOpen = root.popoutVisible;
        // Den Codec erst jetzt lesen -- er interessiert nur den, der hinsieht.
        if (root.popoutVisible)
            {
                Audio.codecsLesen();
                Audio.routenLesen();
            }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: 40 * Theme.cellW
            readonly property Item initialFocusItem: sinkRows.count > 0 ? sinkRows.itemAt(0) : null

            spacing: Theme.cellH * 0.4

            PanelHead {
                rowWidth: panel.rowWidth
                icon: Audio.muted ? Icons.volumeMuted : Icons.volumeHigh
                title: Audio.label(Audio.sink)
                subtitle: "Audio output"
                badge: Audio.muted ? "MUTED" : (Audio.volume + " %")
                badgeColor: Audio.muted ? Theme.red : Theme.accent
            }

            // ── Ausgabe ───────────────────────────────────────────────────

            Row {
                spacing: Theme.cellW

                LevelBar {
                    cells: 24
                    value: Audio.volume
                    maximum: Audio.maxVolume
                    fillColor: Audio.muted ? Theme.muted : Theme.accent
                    onMoved: v => Audio.setVolume(v)
                }

                Line {
                    // Feste Breite und rechtsbuendig, damit der Balken beim
                    // Regeln nicht wandert und die Zahl unter der des
                    // Mikrofons steht. Vorher stand hier ein `padStart(6)`:
                    // das reicht fuer "35%", aber nicht fuer "MIC 100%" --
                    // acht Zeichen in sechs Stellen, und die Beschriftung
                    // klebte am vollen Balken.
                    width: Theme.cellW * 9
                    horizontalAlignment: Text.AlignRight
                    text: Audio.muted ? "muted" : (Audio.volume + "%")
                    color: Audio.muted ? Theme.red : Theme.text
                }
            }

            // ── Mikrofon ──────────────────────────────────────────────────

            Row {
                spacing: Theme.cellW
                visible: Audio.source?.audio !== undefined && Audio.source?.audio !== null

                LevelBar {
                    cells: 24
                    value: Audio.micVolume
                    interactive: false
                    fillColor: Audio.micMuted ? Theme.muted : Theme.green
                }

                Line {
                    width: Theme.cellW * 9
                    horizontalAlignment: Text.AlignRight
                    text: Audio.micMuted ? "muted" : ("MIC " + Audio.micVolume + "%")
                    color: Audio.micMuted ? Theme.red : Theme.fgDim

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.setMicMuted(!Audio.micMuted)
                    }
                }
            }

            // ── Anwendungen ──────────────────────────────────────────────

            Rule {
                visible: Audio.appStreams.length > 0
                rowWidth: panel.rowWidth
                label: "APPLICATIONS"
            }

            Repeater {
                model: Audio.appStreams

                Column {
                    id: appRow

                    required property var modelData

                    width: panel.rowWidth
                    spacing: Theme.cellH * 0.12

                    Line {
                        width: panel.rowWidth
                        text: Audio.label(appRow.modelData)
                        color: appRow.modelData.audio.muted ? Theme.red : Theme.fg
                        elide: Text.ElideRight

                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: Audio.toggleStreamMute(appRow.modelData)
                        }
                    }

                    Row {
                        spacing: Theme.cellW

                        LevelBar {
                            cells: 24
                            value: Audio.streamVolume(appRow.modelData)
                            maximum: Audio.maxVolume
                            fillColor: appRow.modelData.audio.muted ? Theme.muted : Theme.green
                            onMoved: v => Audio.setStreamVolume(appRow.modelData, v)
                        }

                        Line {
                            width: Theme.cellW * 9
                            horizontalAlignment: Text.AlignRight
                            text: appRow.modelData.audio.muted ? "muted" : (Audio.streamVolume(appRow.modelData) + "%")
                            color: appRow.modelData.audio.muted ? Theme.red : Theme.fgDim

                            TapHandler {
                                onTapped: Audio.toggleStreamMute(appRow.modelData)
                            }
                        }
                    }
                }
            }

            Rule {
                visible: Audio.routes.length > 0 && Audio.routeSinks.length > 1
                rowWidth: panel.rowWidth
                label: "OUTPUT ROUTES · CLICK TO SWITCH"
            }

            Repeater {
                model: Audio.routeSinks.length > 1 ? Audio.routes : []
                Rectangle {
                    id: routeRow
                    required property var modelData
                    width: panel.rowWidth
                    height: Theme.cellH * 1.5
                    radius: Theme.radius
                    color: routeHover.hovered ? Theme.hover : "transparent"
                    Line { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.42; text: routeRow.modelData.name; color: Theme.fg; elide: Text.ElideRight }
                    Line { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.55; horizontalAlignment: Text.AlignRight; text: routeRow.modelData.sinkLabel + "  ›"; color: Theme.accent; elide: Text.ElideRight }
                    HoverHandler { id: routeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Audio.cycleRoute(routeRow.modelData) }
                }
            }

            // ── Bluetooth-Codec ───────────────────────────────────────────
            //
            // Nur da, wenn ein Hoerer verbunden ist. Der aktive Codec ist
            // hervorgehoben, ein Klick wechselt -- und der Ton setzt dabei
            // kurz aus, weil PipeWire die Verbindung neu aushandelt.

            Rule {
                visible: Audio.btDa
                rowWidth: panel.rowWidth
                label: "CODEC" + (Audio.btGeraet !== "" ? " · " + Audio.btGeraet : "")
            }

            // Beim Telefonieren steht das Geraet im Headset-Profil: schmale
            // Bandbreite, dafuer mit Mikrofon. Das ist keine Wahl, sondern eine
            // Folge -- also hier auch keine Knoepfe, sondern eine Auskunft.
            Line {
                visible: Audio.btDa && Audio.btTelefonie
                text: "  Telephony (" + Audio.btCodec + ") — narrowband, with microphone"
                color: Theme.yellow
            }

            Row {
                visible: Audio.btDa && !Audio.btTelefonie
                spacing: Theme.cellW

                Repeater {
                    model: Audio.btCodecs

                    delegate: Rectangle {
                        id: codec

                        required property var modelData

                        readonly property bool aktiv: codec.modelData.profil === Audio.btAktiv

                        width: name.implicitWidth + Theme.cellW * 2
                        height: Theme.denseRowHeight
                        radius: Theme.radius
                        color: codec.aktiv ? Theme.selectedSurface(Theme.accent) : (hover.hovered ? Theme.hover : "transparent")
                        border.width: codec.aktiv ? Theme.borderWidth : 0
                        border.color: Theme.readable(Theme.accent, Theme.bg)

                        Line {
                            id: name

                            anchors.centerIn: parent
                            text: codec.modelData.codec
                            color: codec.aktiv ? Theme.selectedForeground(Theme.accent) : Theme.fgDim
                        }

                        HoverHandler {
                            id: hover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: Audio.setzeCodec(codec.modelData.profil)
                        }
                    }
                }
            }

            // Der Hinweis, wegen dem das Ganze hier steht: die Buds koennen
            // AAC und standen trotzdem auf SBC. Ohne diese Zeile faellt so
            // etwas nie auf.
            Line {
                visible: Audio.btSchlechter
                text: "  better codec available: " + (Audio.btCodecs.length > 0 ? Audio.btCodecs[0].codec : "")
                color: Theme.yellow

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: Audio.setzeCodec(Audio.btBeste)
                }
            }

            // ── Geraete ───────────────────────────────────────────────────

            Rule {
                rowWidth: panel.rowWidth
                label: "OUTPUT"
            }

            Repeater {
                id: sinkRows
                model: Audio.sinks

                PanelRow {
                    id: device

                    required property var modelData

                    readonly property bool isCurrent: modelData === Audio.sink

                    width: panel.rowWidth
                    height: Theme.denseRowHeight
                    title: (device.isCurrent ? "▸ " : "  ") + Audio.label(device.modelData)
                    accessibleName: Audio.label(device.modelData)
                    contentLeftPadding: Theme.cellW / 2
                    selected: device.isCurrent
                    interactive: true
                    onTriggered: Audio.setSink(device.modelData)
                }
            }
        }
    }
}
