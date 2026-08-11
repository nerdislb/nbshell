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

    // Breite VORGEBEN, nicht messen lassen. Cells `contentItem` misst sich zwar
    // an seinen Kindern, aber bei Glyphen, deren Schriftgroesse erst aus einer
    // Messung hervorgeht, kam dabei rund nichts heraus: die Zelle blieb schmal,
    // und weil ihr Inhalt zentriert sitzt, quoll er nach links ueber die
    // Arbeitsflaechen-Punkte. `slotChars` ist die Untergrenze, die Cell dafuer
    // schon kennt -- vier Knoepfe zu 1,6 Zellen plus drei Luecken zu 0,6.
    slotChars: Math.round(4 * 1.6 + 3 * 0.6)

    // KEIN `anchors` an dieser Reihe: Cells `contentItem` misst sich an seinen
    // Kindern (`width: childrenRect.width`). Ein Kind, das sich am Eltern-
    // Element ausrichtet, dreht sich damit im Kreis -- die Zelle blieb schmal
    // und der letzte Knopf lag unter dem Nachbarbaustein. Die Zelle zentriert
    // den Inhalt ohnehin selbst.
    // Beim Ueberfahren zeigen, was laeuft -- der Baustein selbst hat dafuer
    // keinen Platz. Auf Hover statt auf Klick, weil hier nichts auszuwaehlen
    // ist: man will es sehen, nicht bedienen.
    popoutOnHover: true
    popout: Component {
        NowPlaying {}
    }

    Row {
        spacing: Theme.cellW * 0.6

        component Knopf: Glyph {
            id: knopf

            signal triggered

            // Jeder Knopf so breit wie der naechste, damit die Reihe ein Raster
            // bleibt: die Glyphen sind verschieden breit, und ohne feste Breite
            // wandern die Abstaende mit dem Symbol (Pause und Play sind nicht
            // gleich breit -- die Reihe zuckte bei jedem Umschalten).
            width: Theme.cellW * 1.6
            horizontalAlignment: Text.AlignHCenter

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
