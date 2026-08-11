import QtQuick
import qs.Common

// Eine Zeile Text -- der Grundbaustein der ganzen Oberflaeche.
//
// Vorher stand in jedem einzelnen Textstueck derselbe Dreiklang:
//
//     font.family: Theme.fontFamily
//     font.pixelSize: Theme.fontSize
//     renderType: Text.NativeRendering
//
// 146 Mal, in fast jeder Datei. Das war nicht nur Rauschen: wer die Schrift
// anfassen will -- eine andere Renderart, ein Buchstabenabstand, ein zweites
// Schriftgewicht -- musste 146 Stellen finden und keine vergessen. Jetzt ist
// es eine.
//
// `NativeRendering` ist der Grund, warum die Schrift auf dem Pixelraster sitzt
// statt weichgezeichnet zu sein -- bei einer Oberflaeche, die sich in
// Zeichenzellen misst, ist das kein Geschmack, sondern Voraussetzung.
//
// Ueberschreiben geht wie bei jedem Text: `font.pixelSize`, `font.bold`,
// `color` einfach am Aufrufort setzen.
Text {
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    renderType: Text.NativeRendering
}
