import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Der Kalender hinter der Uhr: Monatsgitter oben, die Termine des gewaehlten
// Tages darunter.
//
// Das Gitter ist ein Zeichenraster wie alles andere -- jeder Tag ist vier
// Zeichen breit, die Kalenderwoche steht links daneben. Ein Punkt unter der
// Zahl heisst: an dem Tag steht etwas an.
Column {
    id: panel

    property var closePopout: null

    // Angezeigter Monat und ausgewaehlter Tag. Getrennt, weil das Blaettern
    // den gewaehlten Tag nicht verlieren soll.
    property date viewDate: new Date()
    property date selected: new Date()

    readonly property date today: new Date()

    readonly property real cellWidth: Math.round(Theme.cellW * 4)

    // Zwei Zeilen hoch: die Zahl oben, der Punkt darunter. Bei anderthalb
    // Zeilen sass der Punkt auf der Zahl -- "31" sah aus wie "3.1".
    readonly property real cellHeight: Math.round(Theme.cellH * 1.9)

    // Breit genug fuer die Terminzeile darunter, nicht nur fuer das Gitter:
    // Uhrzeit, Farbstreifen und ein Titel, von dem noch etwas uebrig bleibt.
    readonly property real rowWidth: Math.max(cellWidth * 7 + Theme.cellW * 4, Theme.cellW * 54)

    spacing: Theme.cellH * 0.3

    Component.onCompleted: {
        // Beim Oeffnen auf heute zurueck -- und die Termine des angezeigten
        // Monats holen, falls das Fenster woanders steht.
        panel.viewDate = new Date();
        panel.selected = new Date();
        Calendar.ensure(panel.viewDate);
    }

    function moveMonth(delta) {
        const next = new Date(panel.viewDate.getFullYear(), panel.viewDate.getMonth() + delta, 1);
        panel.viewDate = next;
        Calendar.ensure(next);
    }

    // Montag als erster Tag. `getDay()` zaehlt ab Sonntag, deshalb der Dreh.
    function firstColumn(year, month) {
        const day = new Date(year, month, 1).getDay();
        return (day + 6) % 7;
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    component Heading: Text {
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
    }

    component Action: Text {
        id: action

        signal triggered

        color: actionHover.hovered ? Theme.readable(Theme.accent, Theme.bg) : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering

        // Handler statt MouseArea -- siehe die Erklaerung bei den Tageszellen
        // weiter unten: eine MouseArea nimmt das Ueberfahren fuer sich und
        // laesst das Popout glauben, die Maus sei weg.
        HoverHandler {
            id: actionHover

            margin: Theme.cellW / 2
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            margin: Theme.cellW / 2
            onTapped: action.triggered()
        }
    }

    // ── Kopfzeile ─────────────────────────────────────────────────────────

    Item {
        width: panel.rowWidth
        height: Theme.cellH * 1.4

        Heading {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.viewDate.toLocaleString(Qt.locale(Config.value("locale", "de_DE")), "MMMM yyyy").toUpperCase()
            color: Theme.readable(Theme.accent, Theme.bg)
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.cellW * 1.5

            Action {
                text: "[ ‹ ]"
                onTriggered: panel.moveMonth(-1)
            }

            Action {
                text: "[ heute ]"
                onTriggered: {
                    panel.viewDate = new Date();
                    panel.selected = new Date();
                    Calendar.ensure(panel.viewDate);
                }
            }

            Action {
                text: "[ › ]"
                onTriggered: panel.moveMonth(1)
            }
        }
    }

    // ── Monatsgitter ──────────────────────────────────────────────────────

    Column {
        spacing: 0

        // Blaettern mit dem Mausrad -- die Hand liegt ohnehin dort.
        //
        // Ein `WheelHandler` und KEINE MouseArea: eine MouseArea waere ein
        // Kind des Positionierers, bekaeme von ihm eine Position zugewiesen
        // und braeuchte Anker, um die Flaeche zu fuellen -- womit das ganze
        // Gitter nicht mehr gebaut wird. Genau das ist hier zuerst passiert:
        // die Kopfzeile stand da, die Wochen fehlten.
        WheelHandler {
            onWheel: wheelEvent => panel.moveMonth(wheelEvent.angleDelta.y > 0 ? -1 : 1)
        }

        Row {
            spacing: 0

            Item {
                width: Theme.cellW * 4
                height: panel.cellHeight

                Heading {
                    anchors.centerIn: parent
                    text: "KW"
                }
            }

            Repeater {
                model: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

                Item {
                    required property var modelData
                    required property int index

                    width: panel.cellWidth
                    height: panel.cellHeight

                    Heading {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.index >= 5 ? Theme.muted : Theme.fgDim
                    }
                }
            }
        }

        Repeater {
            model: 6

            Row {
                id: week

                required property int index

                readonly property date weekStart: new Date(panel.viewDate.getFullYear(), panel.viewDate.getMonth(), 1 - panel.firstColumn(panel.viewDate.getFullYear(), panel.viewDate.getMonth()) + week.index * 7)

                spacing: 0

                Item {
                    width: Theme.cellW * 4
                    height: panel.cellHeight

                    Heading {
                        anchors.centerIn: parent
                        text: Calendar.isoWeek(week.weekStart)
                        color: Theme.muted
                    }
                }

                Repeater {
                    model: 7

                    Item {
                        id: dayCell

                        required property int index

                        readonly property date day: new Date(week.weekStart.getFullYear(), week.weekStart.getMonth(), week.weekStart.getDate() + dayCell.index)
                        readonly property bool inMonth: day.getMonth() === panel.viewDate.getMonth()
                        readonly property bool isToday: Calendar.sameDay(day, panel.today)
                        readonly property bool isSelected: Calendar.sameDay(day, panel.selected)
                        readonly property bool busy: Calendar.hasEvents(day)

                        width: panel.cellWidth
                        height: panel.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Theme.radius
                            color: dayCell.isSelected ? Theme.alpha(Theme.accent, 0.2) : (dayHover.hovered ? Theme.hover : "transparent")
                            border.width: dayCell.isToday ? Theme.borderWidth : 0
                            border.color: Theme.readable(Theme.accent, Theme.bg)
                        }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -Theme.cellH * 0.3
                            text: dayCell.day.getDate()
                            color: dayCell.inMonth ? (dayCell.isToday ? Theme.readable(Theme.accent, Theme.bg) : Theme.fg) : Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        // Der Punkt sagt nur "da steht etwas an" -- wie viel,
                        // sagt die Liste darunter.
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.cellH * 0.1
                            visible: dayCell.busy
                            text: "·"
                            color: dayCell.inMonth ? Theme.readable(Theme.accent, Theme.bg) : Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            renderType: Text.NativeRendering
                        }

                        // KEINE MouseArea mit `hoverEnabled`: die nimmt das
                        // Ueberfahren fuer sich, und der HoverHandler des
                        // Popoutfensters darueber sieht es nicht mehr. Das
                        // Popout haelt die Maus dann fuer verschwunden und
                        // klappt nach dem Nachlauf zu -- mitten im Lesen.
                        // Handler blockieren einander nicht.
                        HoverHandler {
                            id: dayHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: panel.selected = dayCell.day
                        }
                    }
                }
            }
        }
    }

    // ── Termine des gewaehlten Tages ──────────────────────────────────────

    Rectangle {
        width: panel.rowWidth
        height: Theme.borderWidth
        color: Theme.muted
    }

    Item {
        width: panel.rowWidth
        height: Theme.cellH * 1.4

        Heading {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.selected.toLocaleString(Qt.locale(Config.value("locale", "de_DE")), "dddd, d. MMMM").toUpperCase()
        }

        Action {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Calendar.loading ? "[ liest … ]" : "[ abgleichen ]"
            onTriggered: Calendar.sync()
        }
    }

    Text {
        visible: !Calendar.available
        width: panel.rowWidth
        text: "  " + (Calendar.problem === "khal fehlt" ? "khal ist nicht installiert — pacman -S khal vdirsyncer" : Calendar.problem)
        color: Theme.yellow
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
        wrapMode: Text.WordWrap
    }

    Text {
        visible: Calendar.available && Calendar.eventsOn(panel.selected).length === 0
        text: "  nichts eingetragen"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
    }

    Repeater {
        model: Calendar.eventsOn(panel.selected).slice(0, 8)

        Item {
            id: entry

            required property var modelData

            width: panel.rowWidth
            height: Theme.cellH * 1.3

            Text {
                id: when

                anchors.left: parent.left
                anchors.leftMargin: Theme.cellW
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.cellW * 12
                text: Calendar.timeLabel(entry.modelData)
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
            }

            Rectangle {
                id: mark

                anchors.left: when.right
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.borderWidth * 2
                height: Theme.cellH * 0.8
                color: Calendar.colorFor(entry.modelData.calendar)
            }

            Text {
                anchors.left: mark.right
                anchors.leftMargin: Theme.cellW
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: entry.modelData.title
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
        }
    }

    Text {
        visible: Calendar.eventsOn(panel.selected).length > 8
        text: "  … und " + (Calendar.eventsOn(panel.selected).length - 8) + " weitere"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
    }

    // ── Fusszeile: welche Kalender ueberhaupt dabei sind ───────────────────

    Row {
        visible: Calendar.calendars.length > 0
        spacing: Theme.cellW * 2

        Repeater {
            model: Calendar.calendars

            Row {
                required property var modelData

                spacing: Theme.cellW * 0.5

                Rectangle {
                    width: Theme.cellW * 0.8
                    height: Theme.cellW * 0.8
                    y: Math.round(Theme.cellH * 0.35)
                    color: Calendar.colorFor(parent.modelData)
                }

                Text {
                    text: parent.modelData
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
