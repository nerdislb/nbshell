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
    property bool positionHeld: false

    readonly property real rowWidth: 52 * Theme.cellW

    spacing: Theme.cellH * 0.2

    Component.onCompleted: {
        MediaService.acquirePosition();
        positionHeld = true;
    }

    Component.onDestruction: {
        if (positionHeld)
            MediaService.releasePosition();
    }

    PanelHead {
        rowWidth: panel.rowWidth
        icon: MediaService.playing ? Icons.play : Icons.pause
        title: MediaService.title || "nothing"
        subtitle: MediaService.artist
        badge: MediaService.zeit(MediaService.position)
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
            text: MediaService.zeit(MediaService.position)
            color: Theme.muted
        }

        LevelBar {
            anchors.left: gespielt.right
            anchors.right: gesamt.left
            anchors.rightMargin: Theme.cellW
            anchors.verticalCenter: parent.verticalCenter

            cells: 36
            value: Math.round(MediaService.position)
            maximum: Math.max(1, Math.round(MediaService.length))
            interactive: MediaService.seekable
            onMoved: v => MediaService.seek(v)
        }

        Line {
            id: gesamt

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: MediaService.zeit(MediaService.length)
            color: Theme.muted
        }
    }

    // Lautstaerke -- derselbe Balken, andere Zahl.
    Item {
        width: panel.rowWidth
        height: Theme.cellH * 1.4

        visible: MediaService.volumeSupported

        Line {
            id: vlabel

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            width: Theme.cellW * 6
            text: "Volume"
            color: Theme.muted
        }

        LevelBar {
            anchors.left: vlabel.right
            anchors.verticalCenter: parent.verticalCenter

            cells: 20
            value: Math.round(MediaService.volume * 100)
            maximum: 100
            fillColor: Theme.green
            onMoved: v => MediaService.setVolume(v / 100)
        }

        Line {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text: Math.round(MediaService.volume * 100) + "%"
            color: Theme.muted
        }
    }

}
