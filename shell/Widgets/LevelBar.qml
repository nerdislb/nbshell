import QtQuick
import qs.Common as Common

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
    property color fillColor: Common.Theme.accent
    property bool interactive: true
    property bool keyboardFocusable: false
    property string accessibleName: "Value"
    property int keyboardStep: 5
    readonly property int minimumValue: 0
    readonly property int maximumValue: maximum
    readonly property int stepSize: keyboardStep

    signal moved(int value)

    function moveTo(nextValue) {
        if (!root.interactive || !root.enabled)
            return;
        root.moved(Math.max(0, Math.min(root.maximum, Math.round(nextValue))));
    }

    function moveBy(delta) {
        root.moveTo(root.value + delta);
    }

    activeFocusOnTab: keyboardFocusable && interactive && enabled
    Accessible.role: Accessible.Slider
    Accessible.ignored: !keyboardFocusable
    Accessible.name: accessibleName
    Accessible.description: value + " of " + maximum
    Accessible.focusable: activeFocusOnTab
    Accessible.focused: activeFocus
    Accessible.onIncreaseAction: root.moveBy(root.keyboardStep)
    Accessible.onDecreaseAction: root.moveBy(-root.keyboardStep)

    Keys.onPressed: event => {
        if (!root.keyboardFocusable || !root.interactive)
            return;
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
            root.moveBy(-root.keyboardStep);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
            root.moveBy(root.keyboardStep);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            root.moveTo(0);
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            root.moveTo(root.maximum);
            event.accepted = true;
        }
    }

    // Meter-Stil (Config.meterStyle): "blocks" (TUI-Bloecke) oder "line"
    // (duenne Linie). Nur diese zwei -- die fancy Varianten hat der Visualizer.
    readonly property bool asLine: Common.Config.meterStyle === "line"
    readonly property real ratio: Math.max(0, Math.min(1, maximum > 0 ? value / maximum : 0))

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
    implicitHeight: Common.Theme.cellH

    // Ein Zeichen je Zelle, in zwei Stuecken nebeneinander -- gefuellt und
    // gedaempft. Vorher war es ein Text mit `<font>`-Marken und RichText; zwei
    // schlichte Stuecke messen sich einfacher, und gemessen wird hier ja.
    Row {
        id: bloecke

        visible: !root.asLine
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Line {
            text: "█".repeat(root.filled)
            color: root.fillColor
        }

        Line {
            text: "░".repeat(Math.max(0, root.cells - root.filled))
            color: Common.Theme.muted
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
        height: Math.max(2, Common.Theme.borderWidth * 2)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Common.Theme.alpha(Common.Theme.muted, 0.45)
        }

        Rectangle {
            height: parent.height
            radius: height / 2
            width: Math.round(parent.width * root.ratio)
            color: root.fillColor
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

        onPressed: mouseEvent => {
            if (root.keyboardFocusable)
                root.forceActiveFocus(Qt.MouseFocusReason);
            apply(mouseEvent.x);
        }
        onPositionChanged: mouseEvent => {
            if (pressed)
                apply(mouseEvent.x);
        }
        onWheel: wheelEvent => root.moved(root.value + (wheelEvent.angleDelta.y > 0 ? 5 : -5))
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Common.Theme.borderWidth * 2
        color: "transparent"
        border.width: root.activeFocus ? Common.Theme.borderWidth : 0
        border.color: Common.Theme.focusBorder
        radius: Common.Theme.radius
        visible: root.activeFocus
    }
}
