import QtQuick
import qs.Common
import qs.Services

// Was gerade laeuft -- der Inhalt des Popouts an den Musikbausteinen.
//
// Eine eigene Datei, weil zwei Zellen dasselbe zeigen: die Knoepfe und die
// Visualisierung. Zweimal derselbe Aufbau waere zweimal derselbe spaetere
// Fehler.
//
// Gefuellt wird aus MPRIS, nicht aus unserer Warteschlange -- dann steht hier
// auch etwas, wenn die Musik aus dem Browser kommt. Was nur wir wissen (was als
// Naechstes drankommt), steht darunter und nur dann, wenn wir es wissen.
Column {
    id: panel

    property var closePopout: null

    readonly property real rowWidth: 52 * Theme.cellW

    spacing: Theme.cellH * 0.2

    PanelHead {
        rowWidth: panel.rowWidth
        icon: Music.spielt ? Icons.play : Icons.pause
        title: Music.titel || "nichts"
        subtitle: Music.interpret
        badge: MediaService.zeit(Music.stelle)
    }

    Rule {
        rowWidth: panel.rowWidth
    }

    // Stelle und Laenge. Der Balken ist bedienbar wie im Fenster: hier faehrt
    // die Maus ohnehin schon.
    Item {
        width: panel.rowWidth
        height: Theme.cellH * 1.4

        Line {
            id: gespielt

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            width: Theme.cellW * 6
            text: MediaService.zeit(Music.stelle)
            color: Theme.muted
        }

        LevelBar {
            anchors.left: gespielt.right
            anchors.right: gesamt.left
            anchors.rightMargin: Theme.cellW
            anchors.verticalCenter: parent.verticalCenter

            cells: 36
            value: Math.round(Music.stelle)
            maximum: Math.max(1, Math.round(Music.laenge))
            interactive: Music.spulbar
            onMoved: v => Music.spulen(v)
        }

        Line {
            id: gesamt

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: MediaService.zeit(Music.laenge)
            color: Theme.muted
        }
    }

    // Lautstaerke -- derselbe Balken, andere Zahl.
    Item {
        width: panel.rowWidth
        height: Theme.cellH * 1.4

        visible: Music.lautstaerkeGeht

        Line {
            id: vlabel

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            width: Theme.cellW * 6
            text: "Ton"
            color: Theme.muted
        }

        LevelBar {
            anchors.left: vlabel.right
            anchors.verticalCenter: parent.verticalCenter

            cells: 20
            value: Math.round(Music.lautstaerke * 100)
            maximum: 100
            fillColor: Theme.green
            onMoved: v => Music.setzeLautstaerke(v / 100)
        }

        Line {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: Math.round(Music.lautstaerke * 100) + "%"
            color: Theme.muted
        }
    }

    Rule {
        rowWidth: panel.rowWidth
        label: "als Naechstes"
        visible: panel.naechste.length > 0
    }

    // Was noch kommt: die drei Titel nach dem laufenden. Das weiss nur unsere
    // eigene Warteschlange -- spielt etwas anderes, bleibt der Abschnitt weg.
    readonly property var naechste: {
        if (Music.queue.length === 0 || !Music.current)
            return [];
        const i = Music.queue.indexOf(Music.current);
        return i < 0 ? [] : Music.queue.slice(i + 1, i + 4);
    }

    Repeater {
        model: panel.naechste

        Item {
            id: zeile

            required property var modelData

            width: panel.rowWidth
            height: Theme.cellH * 1.25

            Line {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                width: panel.rowWidth * 0.62
                elide: Text.ElideRight
                text: "  " + zeile.modelData.titel
                color: Theme.fgDim
            }

            Line {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                width: panel.rowWidth * 0.34
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                text: zeile.modelData.interpret
                color: Theme.muted
            }
        }
    }

    Line {
        width: panel.rowWidth
        visible: Music.shuffle && Music.queue.length > 0
        text: "  Zufall an"
        color: Theme.readable(Theme.accent, Theme.bg)
    }
}
