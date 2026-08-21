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
    // Font Awesome's speaker ladder keeps the same painted size at bar scale;
    // the MDI variants rendered visibly smaller beside network and battery.
    readonly property string volumeHigh: cp(0xF028)
    readonly property string volumeMid: cp(0xF027)
    readonly property string volumeLow: cp(0xF026)
    readonly property string volumeMuted: cp(0xF0581)

    // Netz
    readonly property string wifi: cp(0xF05A9)
    readonly property string wifiOff: cp(0xF05AA)
    readonly property string wifiDisconnected: "󰤮"
    readonly property var wifiLevels: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    readonly property string lan: "󰈀"
    readonly property string bluetooth: "󰂯"
    readonly property string bluetoothConnected: "󰂱"
    readonly property string bluetoothOff: "󰂲"
    readonly property string monitor: "󰍹"
    readonly property string monitors: "󰍺"
    readonly property string phone: cp(0xF011C)

    function wifiSignal(strength) {
        // Quickshell currently exposes Wi-Fi strength as 0..1, while some
        // callers and older APIs use 0..100. Accept both here so a healthy
        // 83% connection does not get mistaken for the empty first level.
        const raw = Number(strength || 0);
        const percent = raw > 0 && raw <= 1 ? raw * 100 : raw;
        const index = Math.max(0, Math.min(4, Math.ceil(percent / 20) - 1));
        return root.wifiLevels[index];
    }

    // Meldungen und Ablage
    readonly property string bell: cp(0xF009A)
    readonly property string bellOff: "󰂛"
    readonly property string clipboard: cp(0xF0EA)

    // Aufgaben: ein Kaestchen mit Haken.
    readonly property string todo: cp(0xF0135)
    readonly property string habit: cp(0xF0238) // nf-md-fire (Streaks & Habits)
    readonly property string shield: cp(0xF0498) // nf-md-shield
    readonly property string matrix: cp(0xF0746) // nf-md-view-grid

    // Medien und Aufnahme
    readonly property string play: "󰐊"
    readonly property string pause: "󰏤"

    // Wiedergabe vor und zurueck sowie der Zufall. Nachgesehen statt geraten:
    // die beiden naheliegenden Unicode-Zeichen U+23EE/U+23ED kennt die Schrift
    // gar nicht -- gerendert kam nichts. Die MDI-Glyphen sind da.
    readonly property string skipPrevious: "󰒮"
    readonly property string skipNext: "󰒭"
    readonly property string shuffle: cp(0xF049D)
    readonly property string camera: cp(0xF0100)
    readonly property string record: "󰻂"

    // Wachhalten. Die Tasse (nf-md-coffee) ist bei 13 px noch als Tasse zu
    // erkennen -- mit Dampf darueber, und genau der macht sie eindeutig. Das
    // zZz daneben ist absichtlich das leisere Zeichen: es steht fuer den
    // Normalfall, und der soll nicht auffallen.
    readonly property string coffee: cp(0xF0176)
    readonly property string stayAwake: "󰅶"
    readonly property string sleep: cp(0xF04B2)
    readonly property string sleepOff: cp(0xF04B3)

    // In der Naehe. Der Papierflieger (F048A) waere naheliegender, wird bei
    // 13 px aber zu einem duennen Strich -- die Knotengrafik haelt sich.
    readonly property string share: cp(0xF0497)

    // Updates
    readonly property string download: cp(0xF01DA)
    readonly property string refresh: cp(0xF021)
    readonly property string agent: "󱚣"
    readonly property string check: "󰄬"
    readonly property string circleOutline: "󰄱"

    // Etwas ist kaputt. Das Warndreieck (nf-md-alert) und nicht das Achteck
    // daneben: bei 14 px bleibt vom Achteck ein Klecks mit Punkt, das Dreieck
    // behaelt seine Form. Verwechseln kann man es mit nichts sonst in der
    // Leiste -- die Glocke der Meldungen ist rund.
    readonly property string alert: cp(0xF0026)

    // Akku. Die Reihe F0079..F0082 ist voll, 10 %, 20 % … 90 % -- also nicht
    // fortlaufend nach Prozent sortiert, sondern "voll" zuerst. Daher die
    // Fallunterscheidung statt einer Rechnung auf dem Zeichencode.
    readonly property string batteryCharging: "󰂅"
    readonly property var batteryLevels: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    readonly property var batteryChargingLevels: ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]

    function battery(percent) {
        const step = Math.max(0, Math.min(9, Math.floor(Number(percent || 0) / 10)));
        return root.batteryLevels[step];
    }

    function batteryCharge(percent) {
        const step = Math.max(0, Math.min(9, Math.floor(Number(percent || 0) / 10)));
        return root.batteryChargingLevels[step];
    }

    // Mond. 28 Sicheln aus dem Wetterteil der Schrift (`nf-weather-moon_*`),
    // von Neumond ueber Vollmond zurueck zum Neumond. Hier ist der Zeichenblock
    // ausnahmsweise wirklich der Reihe nach sortiert, also genuegt eine
    // Addition -- anders als beim Akku darueber.
    //
    // Nachgesehen statt geraten: alle 28 stecken in Inconsolata Nerd Font, und
    // auch bei 14 px bleibt die Sichel eine Sichel. Die naheliegenden Material-
    // Zeichen (nf-md-moon-*) waren es NICHT -- die Codepunkte, die man dafuer
    // haelt, liefern ein Dokumentsymbol.
    readonly property int moonSteps: 28

    function moon(index) {
        const i = ((Math.round(index) % root.moonSteps) + root.moonSteps) % root.moonSteps;
        return cp(0xE38D + i);
    }
}
