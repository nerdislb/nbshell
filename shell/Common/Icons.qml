pragma Singleton

import QtQuick
import Quickshell

// Die Symbole der Leiste, an einer Stelle.
//
// Alle stammen aus dem Material-Design-Teil der Nerd-Font-Schrift (`nf-md-*`),
// bis auf die Zwischenablage -- die gibt es dort nur als Klemmbrett mit
// Beschriftung, das bei 14 px zu Brei wird.
//
// **Ein Zeichen wird nach seinem Aussehen bei 14 px gewaehlt, nicht nach
// seinem Namen.** Feine Striche verschwinden in der Leiste: der erste Versuch
// beim Updater (`nf-fa-download`) hinterliess nur einen Fleck. Wer hier etwas
// austauscht, sieht es sich vorher in Leistengroesse an -- gerendert, nicht in
// der Zeichentabelle des Browsers.
Singleton {
    id: root

    function cp(code) {
        return String.fromCodePoint(code);
    }

    // Uhr, Last, Tastatur, Farben
    readonly property string clock: cp(0xF0150)
    // Nicht der Prozessor-Chip (`nf-md-cpu-64-bit`) und nicht der Speicher-
    // Chip: beide haben so feine Innenzeichnung, dass in der Leiste ein
    // dunkler Klecks uebrig bleibt. Ein Tacho und ein Stapel sind bei 14 px
    // noch zu erkennen -- und darum geht es, nicht um den Namen des Zeichens.
    readonly property string cpu: cp(0xF04C5)
    readonly property string memory: cp(0xF01BC)
    readonly property string keyboard: cp(0xF030C)
    readonly property string palette: cp(0xF03D8)

    // Ton
    readonly property string volumeHigh: cp(0xF057E)
    readonly property string volumeLow: cp(0xF0580)
    readonly property string volumeMuted: cp(0xF0581)

    // Netz
    readonly property string wifi: cp(0xF05A9)
    readonly property string wifiOff: cp(0xF05AA)
    readonly property string lan: cp(0xF0318)

    // Meldungen und Ablage
    readonly property string bell: cp(0xF009A)
    readonly property string bellOff: cp(0xF009B)
    readonly property string clipboard: cp(0xF0EA)

    // Aufgaben: ein Kaestchen mit Haken. Der naheliegende `nf-md-format-list-
    // checks` (F05C7) ist in Leistengroesse ein Fleck -- drei duenne Linien und
    // ein Haken auf 13 px sind nicht mehr auseinanderzuhalten. Das Kaestchen
    // behaelt seine Form.
    readonly property string todo: cp(0xF0135)

    // Medien und Aufnahme
    readonly property string play: cp(0xF040A)
    readonly property string pause: cp(0xF03E4)
    readonly property string camera: cp(0xF0100)
    readonly property string record: cp(0xF044A)

    // Wachhalten. Die Tasse (nf-md-coffee) ist bei 13 px noch als Tasse zu
    // erkennen -- mit Dampf darueber, und genau der macht sie eindeutig. Das
    // zZz daneben ist absichtlich das leisere Zeichen: es steht fuer den
    // Normalfall, und der soll nicht auffallen.
    readonly property string coffee: cp(0xF0176)
    readonly property string sleep: cp(0xF04B2)
    readonly property string sleepOff: cp(0xF04B3)

    // Updates
    readonly property string download: cp(0xF01DA)
    readonly property string refresh: cp(0xF0450)

    // Akku. Die Reihe F0079..F0082 ist voll, 10 %, 20 % … 90 % -- also nicht
    // fortlaufend nach Prozent sortiert, sondern "voll" zuerst. Daher die
    // Fallunterscheidung statt einer Rechnung auf dem Zeichencode.
    readonly property string batteryCharging: cp(0xF0084)

    function battery(percent) {
        if (percent >= 95)
            return cp(0xF0079);
        const step = Math.max(1, Math.min(9, Math.round(percent / 10)));
        return cp(0xF0079 + step);
    }
}
