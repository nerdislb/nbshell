import QtQuick
import qs.Common

// Ein Symbol aus der Nerd-Font-Schrift, auf Zeilenhoehe gebracht.
//
// Warum nicht einfach `font.pixelSize` setzen: jedes Zeichen bemalt einen
// anderen Anteil seiner Zeile. Zwei Symbole mit derselben Schriftgroesse sind
// darum verschieden gross -- ein Pfeil fuellt die Zeile fast aus, ein Punkt
// sitzt winzig in der Mitte. Gemessen wird deshalb, wie hoch die Zeichnung
// dieses einen Zeichens bei einer Probegroesse wirklich ist, und daraus ergibt
// sich die Schriftgroesse fuer die gewuenschte Hoehe.
//
// Derselbe Trick wie im KI-Baustein -- dort war er noetig, um den Fuellstand
// zu treffen, hier, damit das Symbol so hoch steht wie der Text daneben.
Text {
    id: root

    // Gewuenschte Hoehe der Zeichnung, nicht der Zeile.
    property real inkHeight: Math.round(Theme.cellH * 0.72)

    // Die Probe haengt NICHT an der eigenen Schriftgroesse, sonst drehte sich
    // die Rechnung im Kreis.
    readonly property real inkRatio: Math.max(0.2, probe.tightBoundingRect.height / 100)

    font.family: Theme.fontFamily
    font.pixelSize: Math.round(root.inkHeight / root.inkRatio)
    // QtRendering: die Symbole haben feine Rundungen, die das Hinting der
    // nativen Zeichnung bei kleinen Groessen platt drueckt.
    renderType: Text.QtRendering
    color: Theme.fg

    TextMetrics {
        id: probe

        font.family: Theme.fontFamily
        font.pixelSize: 100
        text: root.text
    }
}
