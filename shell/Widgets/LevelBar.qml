import QtQuick
import qs.Common

// Ein Balken aus Bloecken, wie ihn ein Terminalprogramm zeichnen wuerde.
//
// Keine Fortschrittsleiste mit abgerundeten Ecken, sondern `cells` Zeichen
// nebeneinander: gefuellt bis zum Wert, danach gedaempft. Ziehen und Klicken
// setzt den Wert -- so lange die Maus gedrueckt ist, folgt er ihr.
Item {
    id: root

    property int value: 0
    property int maximum: 100
    property int cells: 20
    property color fillColor: Theme.accent
    property bool interactive: true

    signal moved(int value)

    // Balken-Stil (Config.meterStyle): blocks (TUI) | line | dots | wave.
    // blocks ist der Rueckfall fuer alles Unbekannte.
    readonly property string meterStyle: Config.meterStyle
    readonly property bool asLine: meterStyle === "line"
    readonly property bool asDots: meterStyle === "dots"
    readonly property bool asWave: meterStyle === "wave"
    readonly property bool asBlocks: !asLine && !asDots && !asWave

    readonly property real ratio: Math.max(0, Math.min(1, maximum > 0 ? value / maximum : 0))
    readonly property int filledDots: Math.round(cells * ratio)

    readonly property int filled: Math.round(cells * Math.max(0, Math.min(maximum, value)) / maximum)

    // So breit, wie die Bloecke WIRKLICH gemalt werden -- nicht `cells *
    // cellW`.
    //
    // An diesem Unterschied ging eine Zeile kaputt: `cellW` ist die
    // Vorschubbreite der Ziffer 0 (6,5 px), die Bloecke legt Qt aber mit rund
    // 7 px je Zeichen um. Bei 24 Zellen sind das 168 statt 156 -- knapp zwei
    // Zeichen, die ueber den eigenen Kasten hinausragen, waehrend der Nachbar
    // in der Reihe brav nach 156 px gesetzt wird und dann unter dem Balkenende
    // liegt. Auch die Tinte des Vollblocks ist breiter als sein Vorschub
    // (gerendert 7 px bei 6,5 px Vorschub), es liegt also nicht bloss an der
    // Rundung der Zeichensatzdarstellung.
    //
    // Gesehen hat man es nur am Mikrofon: dessen Balken steht meist auf 100 %,
    // und ein voller Balken ist sichtbar, ein leerer nicht.
    //
    // Nachgemessen statt vermutet: Soll 156, gemalt 167,6.
    implicitWidth: bloecke.implicitWidth
    implicitHeight: Theme.cellH

    // Ein Zeichen je Zelle, in zwei Stuecken nebeneinander -- gefuellt und
    // gedaempft. Vorher war es ein Text mit `<font>`-Marken und RichText; zwei
    // schlichte Stuecke messen sich einfacher, und gemessen wird hier ja.
    Row {
        id: bloecke

        visible: root.asBlocks
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Line {
            text: "█".repeat(root.filled)
            color: root.fillColor
        }

        Line {
            text: "░".repeat(Math.max(0, root.cells - root.filled))
            color: Theme.muted
        }
    }

    // Omarchy-Variante: eine duenne Linie (gedaempfter Track + gefuellter Teil)
    // statt Bloecken. Gleiche Breite wie die Bloecke, damit das Layout beim
    // Umschalten nicht springt (`bloecke.implicitWidth` gilt auch unsichtbar).
    Item {
        id: lineBar

        visible: root.asLine
        anchors.verticalCenter: parent.verticalCenter
        width: bloecke.implicitWidth
        height: Math.max(2, Theme.borderWidth * 2)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.alpha(Theme.muted, 0.45)
        }

        Rectangle {
            height: parent.height
            radius: height / 2
            width: Math.round(parent.width * root.ratio)
            color: root.fillColor
        }
    }

    // Punkte: gefuellte Kreise bis zum Wert, danach leere -- wie die Bloecke,
    // nur runder.
    Row {
        visible: root.asDots
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Line {
            text: "●".repeat(root.filledDots)
            color: root.fillColor
        }

        Line {
            text: "○".repeat(Math.max(0, root.cells - root.filledDots))
            color: Theme.muted
        }
    }

    // Welle: eine Sinuslinie ueber die ganze Breite (gedaempfter Track), der
    // gefuellte Teil bis zum Wert in Akzentfarbe darueber.
    Canvas {
        id: waveBar

        visible: root.asWave
        anchors.verticalCenter: parent.verticalCenter
        width: bloecke.implicitWidth
        height: Math.round(Theme.cellH * 0.7)

        readonly property real fillX: width * root.ratio

        function drawWave(ctx, x0, x1, mid, amp, wl, stroke) {
            if (x1 <= x0)
                return;
            ctx.beginPath();
            ctx.strokeStyle = stroke;
            for (var x = x0; x <= x1; x += 1) {
                const y = mid + amp * Math.sin((x / wl) * 2 * Math.PI);
                if (x === x0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const wl = Theme.cellW * 3;      // Wellenlaenge
            const mid = height / 2;
            const amp = height * 0.30;
            ctx.lineWidth = Math.max(1.5, Theme.borderWidth * 1.5);
            ctx.lineCap = "round";
            drawWave(ctx, 0, width, mid, amp, wl, Theme.alpha(Theme.muted, 0.6));
            drawWave(ctx, 0, fillX, mid, amp, wl, root.fillColor);
        }

        onFillXChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible)
            requestPaint()
        Component.onCompleted: requestPaint()

        // Bei Themewechsel neu zeichnen (Farben aendern sich, Canvas nicht von selbst).
        Connections {
            target: root
            function onFillColorChanged() {
                waveBar.requestPaint();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton

        function apply(x) {
            const share = Math.max(0, Math.min(1, x / root.width));
            root.moved(Math.round(share * root.maximum));
        }

        onPressed: mouseEvent => apply(mouseEvent.x)
        onPositionChanged: mouseEvent => {
            if (pressed)
                apply(mouseEvent.x);
        }
        onWheel: wheelEvent => root.moved(root.value + (wheelEvent.angleDelta.y > 0 ? 5 : -5))
    }
}
