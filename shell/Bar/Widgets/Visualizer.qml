import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Der Ausschlag als Blockzeichen.
//
// Keine gezeichneten Rechtecke, sondern ein Text aus ▁▂▃▄▅▆▇█ -- so wuerde es
// ein Terminalprogramm machen, und so passt es zu allem anderen hier: die
// Balken sitzen im selben Zeichenraster wie die Uhr daneben und wachsen mit
// der Schriftgroesse mit, ohne dass jemand eine Pixelhoehe nachzieht.
//
// Eine Zeile Text je Bild statt zwoelf Rechtecken mit je einer Hoehenbindung:
// bei dreissig Bildern in der Sekunde ist das der Unterschied zwischen einer
// Eigenschaft und 360 Bindungen.
Cell {
    id: root

    // Ohne Ton keine Balken -- und ohne Balken keine leere Zelle in der Leiste.
    shown: Cava.levels.length > 0

    // Die Breite steht fest, sonst zappelt die halbe Leiste im Takt der Musik:
    // die Nachbarn wuerden bei jedem Bild neu ausgerichtet.
    slotChars: Cava.bars

    // Beim Ueberfahren zeigen, was laeuft -- der Baustein selbst hat dafuer
    // keinen Platz. Auf Hover statt auf Klick, weil hier nichts auszuwaehlen
    // ist: man will es sehen, nicht bedienen.
    popoutOnHover: true
    popout: Component {
        NowPlaying {}
    }

    Line {
        // Die Blockschrift hat acht Stufen, cava liefert 0 bis 7 -- deshalb
        // wird hier nicht gerechnet, sondern nachgeschlagen.
        readonly property string stufen: "▁▂▃▄▅▆▇█"

        text: {
            let s = "";
            for (const v of Cava.levels)
                s += stufen.charAt(Math.max(0, Math.min(7, v)));
            return s;
        }

        // Blockzeichen fuellen ihre Zeile vollstaendig aus und ragen dabei
        // ueber die Zellenhoehe hinaus -- die Balken hingen unten aus der
        // Leiste heraus. Etwas kleiner gesetzt und auf die Zellenhoehe
        // begrenzt sitzen sie drin; `clip` faengt den Rest ab.
        font.pixelSize: Math.round(Theme.fontSize * 0.8)
        height: Theme.cellH
        verticalAlignment: Text.AlignVCenter
        clip: true

        color: Theme.readable(Theme.accent, Theme.bg)
    }
}
