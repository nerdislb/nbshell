import QtQuick
import QtQuick.Shapes
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

    // Eigener Stil (Einstellung "Visualizer", getrennt von den Metern):
    // "blocks" = Text-Zeile (Vorgabe, am leichtesten), sonst DEKLARATIVE
    // Elemente (line/dots = Rechtecke, wave = Shape) -- bewusst KEIN per-Frame-
    // Canvas: der fraß bei laufender Musik ueber Minuten den Speicher voll (2 GB+).
    readonly property string vizStyle: Config.visualizerStyle
    readonly property color ink: Theme.readable(Theme.accent, Theme.bg)

    Line {
        // Die Blockschrift hat acht Stufen, cava liefert 0 bis 7 -- deshalb
        // wird hier nicht gerechnet, sondern nachgeschlagen.
        readonly property string stufen: "▁▂▃▄▅▆▇█"

        visible: root.vizStyle === "blocks"

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

    // line = senkrechte Balken, dots = Punkte an den Spitzen -- deklarative
    // Rechtecke (GPU-komponiert, kein Neuzeichnen pro Frame). Stabiles Modell
    // (Cava.bars): nur die Hoehen-/y-Bindungen aendern sich je Bild.
    Row {
        visible: root.vizStyle === "line" || root.vizStyle === "dots"
        width: root.slotChars * Theme.cellW
        height: Theme.cellH
        spacing: 0

        Repeater {
            model: Cava.bars

            Item {
                required property int index
                width: (root.slotChars * Theme.cellW) / Math.max(1, Cava.bars)
                height: Theme.cellH

                readonly property real t: {
                    const v = Cava.levels[index];
                    return v === undefined ? 0 : Math.max(0, Math.min(7, v)) / 7;
                }

                // line: Balken vom Boden bis zur Hoehe des Werts
                Rectangle {
                    visible: root.vizStyle === "line"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: parent.height * 0.08
                    width: Math.max(1.5, parent.width * 0.5)
                    height: Math.max(1.5, parent.height * 0.84 * parent.t)
                    radius: width / 2
                    color: root.ink
                }

                // dots: Punkt auf Hoehe des Werts
                Rectangle {
                    visible: root.vizStyle === "dots"
                    width: Math.max(2, parent.width * 0.42)
                    height: width
                    radius: width / 2
                    color: root.ink
                    x: (parent.width - width) / 2
                    y: parent.height * 0.92 - parent.t * (parent.height * 0.84) - height / 2
                }
            }
        }
    }

    // wave: Linie durch die Spitzen -- ein GPU-Shape (PathPolyline), ebenfalls
    // ohne per-Frame-Canvas.
    Shape {
        visible: root.vizStyle === "wave"
        width: root.slotChars * Theme.cellW
        height: Theme.cellH

        ShapePath {
            strokeColor: root.ink
            strokeWidth: Math.max(1.5, Theme.borderWidth * 1.5)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: {
                    const lv = Cava.levels;
                    const n = lv.length;
                    if (n === 0)
                        return [];
                    const w = root.slotChars * Theme.cellW;
                    const h = Theme.cellH;
                    const step = w / n;
                    const pts = [];
                    for (var i = 0; i < n; i++) {
                        const x = step * i + step / 2;
                        const tt = Math.max(0, Math.min(7, lv[i])) / 7;
                        pts.push(Qt.point(x, h * 0.92 - tt * (h * 0.84)));
                    }
                    return pts;
                }
            }
        }
    }
}
