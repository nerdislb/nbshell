import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Zurueck, Pause, Weiter -- direkt in der Leiste.
//
// Der Baustein `media` daneben zeigt, WAS laeuft, und schaltet auf Klick um.
// Das reicht, solange man nur pausieren will; einen Titel zurueck kam man
// bisher nur ueber die Medientasten der Tastatur, die nicht jede Tastatur hat.
//
// Drei Knoepfe in EINER Zelle, nicht drei Zellen nebeneinander: drei gerahmte
// Kaesten fuer eine zusammengehoerige Sache waeren dreimal derselbe Rahmen.
// `Cell` nimmt eigenen Inhalt an (`content`), der Rahmen bleibt einer.
//
// Gesteuert wird ueber MPRIS, nicht ueber unser mpv -- damit gelten die
// Knoepfe auch fuer den Browser, Spotify oder was sonst gerade spielt. Genau
// dafuer ist die Schnittstelle da.
Cell {
    id: root

    // Ohne Abspieler waeren es drei tote Knoepfe.
    shown: MediaService.active
    quiet: !MediaService.playing

    // KEIN `anchors` an dieser Reihe: Cells `contentItem` misst sich an seinen
    // Kindern (`width: childrenRect.width`). Ein Kind, das sich am Eltern-
    // Element ausrichtet, dreht sich damit im Kreis -- die Zelle blieb schmal
    // und der letzte Knopf lag unter dem Nachbarbaustein. Die Zelle zentriert
    // den Inhalt ohnehin selbst.
    Row {
        spacing: Theme.cellW * 0.8

        component Knopf: Glyph {
            id: knopf

            signal triggered

            // Nach aussen gereicht, weil die ids einer inline-Komponente an
            // der Aufrufstelle nicht sichtbar sind -- der Zufallsknopf unten
            // braucht den Zustand fuer seine eigene Farbe.
            property alias hovered: maus.hovered

            // Der Zeiger wird heller, wenn man drueberfaehrt -- sonst sieht
            // man drei Zeichen und weiss nicht, dass sie etwas tun.
            color: maus.hovered ? Theme.readable(Theme.accent, Theme.bg) : Theme.fgDim

            HoverHandler {
                id: maus

                margin: Theme.cellW / 2
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                margin: Theme.cellW / 2
                onTapped: knopf.triggered()
            }
        }

        Knopf {
            text: Icons.skipPrevious
            onTriggered: MediaService.previous()
        }

        Knopf {
            text: MediaService.playing ? Icons.pause : Icons.play
            onTriggered: MediaService.playPause()
        }

        Knopf {
            text: Icons.skipNext
            onTriggered: MediaService.next()
        }

        // Der Zufall gilt nur fuer unsere eigene Warteschlange -- MPRIS kann
        // ihn nicht, und ein Knopf, der bei fremden Spielern nichts taete,
        // waere eine Luege. Deshalb nur sichtbar, wenn wir selbst spielen.
        Knopf {
            visible: Music.queue.length > 0

            text: Icons.shuffle
            color: Music.shuffle ? Theme.readable(Theme.accent, Theme.bg) : (hovered ? Theme.fg : Theme.muted)
            onTriggered: Music.toggleShuffle()
        }
    }
}
