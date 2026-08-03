import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets

// Wetter -- Temperatur in der Leiste, Einzelheiten und fuenf Tage im Popout.
//
// Ein Plugin, kein eingebauter Baustein: es liegt unter
// ~/.config/nbshell/plugins/wetter und ueberlebt jedes `install.sh`.
//
// **Es geht ins Netz.** Als einziger Teil der Shell. Was den Rechner
// verlaesst, steht in weather.sh -- kurz: der Ortsname einmal, danach die
// Koordinaten. Der Ort kommt aus der Config (`weatherPlace`) und wird von Hand
// gesetzt; nichts fragt das Geraet nach seinem Standort.
Cell {
    id: root

    readonly property string place: Config.value("weatherPlace", "Wien")

    // Wie oft nachgesehen wird. Open-Meteo rechnet stuendlich, oefter als
    // viertelstuendlich zu fragen bringt also nichts.
    readonly property int interval: Config.value("weatherInterval", 900000)

    property var data: ({})
    property bool loading: false

    readonly property bool ready: data.ok === true
    readonly property int code: ready ? (data.code ?? 0) : -1
    readonly property bool day: data.tag !== false

    label: "WTR"
    icon: root.ready ? root.glyph(root.code, root.day) : String.fromCodePoint(0xE30D)
    text: root.ready ? (Math.round(data.temp) + "°") : (root.loading ? "…" : "—")
    color: Theme.text
    interactive: true
    slotChars: 4

    // Nur still, wenn noch nie etwas ankam -- eine Zelle, die "—" zeigt, weil
    // gerade kein Netz da ist, soll stehen bleiben.
    quiet: !ready

    onClicked: root.refresh()

    Component.onCompleted: root.refresh()

    function refresh() {
        if (root.loading)
            return;
        root.loading = true;
        // Der Zwischenspeicher liegt im Skript: ein Klick fragt trotzdem neu,
        // ein Zeitgeber nur, wenn der Stand alt genug ist.
        proc.command = ["bash", Qt.resolvedUrl("weather.sh").toString().replace("file://", ""), "current", root.place, "300"];
        proc.running = true;
    }

    // WMO-Wettercodes. Die Tabelle ist kurz gehalten: was nicht drinsteht,
    // faellt auf die naechstliegende Stufe zurueck.
    function describe(code) {
        switch (code) {
        case 0:
            return "klar";
        case 1:
            return "ueberwiegend klar";
        case 2:
            return "teils bewoelkt";
        case 3:
            return "bedeckt";
        case 45:
        case 48:
            return "Nebel";
        case 51:
        case 53:
        case 55:
            return "Niesel";
        case 56:
        case 57:
            return "gefrierender Niesel";
        case 61:
            return "leichter Regen";
        case 63:
            return "Regen";
        case 65:
            return "starker Regen";
        case 66:
        case 67:
            return "gefrierender Regen";
        case 71:
            return "leichter Schnee";
        case 73:
            return "Schnee";
        case 75:
            return "starker Schnee";
        case 77:
            return "Schneegriesel";
        case 80:
        case 81:
            return "Schauer";
        case 82:
            return "kraeftige Schauer";
        case 85:
        case 86:
            return "Schneeschauer";
        case 95:
            return "Gewitter";
        case 96:
        case 99:
            return "Gewitter mit Hagel";
        }
        return "unbekannt";
    }

    // Die Wettersymbole der Nerd-Font-Schrift (nf-weather-*). Ausgesucht nach
    // dem Aussehen bei 14 px -- die Reihe hat viele Varianten, von denen die
    // meisten in Leistengroesse gleich aussehen.
    function glyph(code, isDay) {
        switch (code) {
        case 0:
            return String.fromCodePoint(isDay ? 0xE30D : 0xE32B);
        case 1:
        case 2:
            return String.fromCodePoint(0xE302);
        case 3:
            return String.fromCodePoint(0xE312);
        case 45:
        case 48:
            return String.fromCodePoint(0xE313);
        case 51:
        case 53:
        case 55:
        case 56:
        case 57:
        case 80:
        case 81:
        case 82:
            return String.fromCodePoint(0xE319);
        case 61:
        case 63:
        case 65:
        case 66:
        case 67:
            return String.fromCodePoint(0xE318);
        case 71:
        case 73:
        case 75:
        case 77:
        case 85:
        case 86:
            return String.fromCodePoint(0xE31A);
        case 95:
        case 96:
        case 99:
            return String.fromCodePoint(0xE31D);
        }
        return String.fromCodePoint(0xE374);
    }

    function clock(iso) {
        if (!iso)
            return "—";
        return Qt.formatDateTime(new Date(iso), "HH:mm");
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(text);
                } catch (e) {
                    console.warn("nbshell/wetter: Antwort unlesbar —", e);
                }
                root.loading = false;
            }
        }
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: Theme.cellW * 40
            readonly property var d: root.data

            spacing: Theme.cellH * 0.25

            component Line: Text {
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Item {
                width: panel.rowWidth
                height: Theme.cellH * 1.4

                Line {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.ready ? String(panel.d.ort).toUpperCase() : "WETTER"
                    color: Theme.readable(Theme.accent, Theme.bg)
                    elide: Text.ElideRight
                }

                Line {
                    id: reload

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.loading ? "[ holt … ]" : "[ neu ]"
                    color: reloadHover.hovered ? Theme.readable(Theme.accent, Theme.bg) : Theme.fgDim

                    HoverHandler {
                        id: reloadHover

                        margin: Theme.cellW / 2
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        margin: Theme.cellW / 2
                        onTapped: root.refresh()
                    }
                }
            }

            Line {
                visible: !root.ready
                width: panel.rowWidth
                text: panel.d.grund ? ("  " + panel.d.grund) : "  noch nichts geholt"
                color: Theme.yellow
                wrapMode: Text.WordWrap
            }

            // ── Jetzt ─────────────────────────────────────────────────────

            Row {
                visible: root.ready
                spacing: Theme.cellW * 1.5

                Item {
                    width: big.inkWidth
                    height: Theme.cellH * 2.4

                    Glyph {
                        id: big

                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: big.inkOffsetX
                        inkHeight: Theme.cellH * 1.6
                        text: root.glyph(root.code, root.day)
                        color: Theme.readable(Theme.accent, Theme.bg)
                    }
                }

                Column {
                    spacing: 0

                    Line {
                        text: root.ready ? (panel.d.temp + " °C   " + root.describe(root.code)) : ""
                    }

                    Line {
                        text: root.ready ? ("gefuehlt " + panel.d.gefuehlt + " °C") : ""
                        color: Theme.fgDim
                    }

                    Line {
                        text: root.ready ? ("Wind " + panel.d.wind + " km/h   Feuchte " + panel.d.feuchte + " %") : ""
                        color: Theme.fgDim
                    }
                }
            }

            Line {
                visible: root.ready
                text: "  auf " + root.clock(panel.d.auf) + "   unter " + root.clock(panel.d.unter) + "   Stand " + root.clock(panel.d.stand)
                color: Theme.muted
            }

            Rectangle {
                visible: root.ready
                width: panel.rowWidth
                height: Theme.borderWidth
                color: Theme.muted
            }

            // ── Fuenf Tage ────────────────────────────────────────────────

            Repeater {
                model: root.ready ? (panel.d.tage ?? []) : []

                Item {
                    id: dayRow

                    required property var modelData
                    required property int index

                    width: panel.rowWidth
                    height: Theme.cellH * 1.3

                    Line {
                        id: name

                        anchors.left: parent.left
                        anchors.leftMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.cellW * 6
                        text: dayRow.index === 0 ? "heute" : new Date(dayRow.modelData.datum).toLocaleString(Qt.locale(Config.value("locale", "de_DE")), "ddd")
                        color: dayRow.index === 0 ? Theme.fg : Theme.fgDim
                    }

                    Item {
                        id: mark

                        anchors.left: name.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.cellW * 3
                        height: Theme.cellH

                        Glyph {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: inkOffsetX
                            text: root.glyph(dayRow.modelData.code, true)
                            // Nicht gedaempft: die Wettersymbole sind fein
                            // gezeichnet und verschwinden sonst.
                            color: Theme.fg
                        }
                    }

                    Line {
                        id: range

                        anchors.left: mark.right
                        anchors.leftMargin: Theme.cellW
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(dayRow.modelData.max) + "° / " + Math.round(dayRow.modelData.min) + "°"
                    }

                    Line {
                        anchors.left: range.right
                        anchors.leftMargin: Theme.cellW * 2
                        anchors.verticalCenter: parent.verticalCenter
                        visible: dayRow.modelData.regen !== null && dayRow.modelData.regen > 0
                        text: dayRow.modelData.regen + " % Regen"
                        color: Theme.fgDim
                    }
                }
            }

            Line {
                visible: root.ready
                text: "  Daten von open-meteo.com"
                color: Theme.muted
            }
        }
    }
}
