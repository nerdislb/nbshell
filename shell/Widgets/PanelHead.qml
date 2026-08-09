import QtQuick
import qs.Common

// Die Kopfzeile eines Popouts: Symbol und Titel, darunter gedimmt der
// Zusammenhang, rechts ein gerahmter Kurzwert.
//
//    Ethernet                                        [ 2.5gbit ]
//    WIRING BITS
//
// Zwei Dinge stehen dahinter, beide aus Omarchy 4:
//
//   * Der Untertitel trennt SACHE von ZUSAMMENHANG. "Netz" und der Name des
//     Netzes sind nicht dasselbe, standen bei uns aber in einer Zeile und
//     mussten sich die Breite teilen.
//   * Der Kurzwert rechts ist die eine Zahl, die man ohne Lesen erkennen
//     will -- Verbindungsgeschwindigkeit, Anzahl der Updates, Laufzeit einer
//     Aufnahme. Der Rahmen macht ihn zur Marke statt zu noch einem Wort.
//
// Alles ausser dem Titel ist freiwillig; was leer bleibt, nimmt keinen Platz.
Item {
    id: root

    property real rowWidth: 0
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string badge: ""
    property color badgeColor: Theme.fgDim

    width: root.rowWidth
    height: Theme.cellH * (root.subtitle !== "" ? 2.6 : 1.5)

    Glyph {
        id: mark

        anchors.left: parent.left
        anchors.top: parent.top
        visible: root.icon !== ""
        text: root.icon
        color: Theme.accent
    }

    Text {
        id: title

        anchors.left: root.icon !== "" ? mark.right : parent.left
        anchors.leftMargin: root.icon !== "" ? Theme.cellW : 0
        anchors.top: parent.top
        anchors.right: badge.left
        anchors.rightMargin: Theme.cellW
        text: root.title
        color: Theme.fgBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    Text {
        anchors.left: title.left
        anchors.top: title.bottom
        anchors.right: parent.right
        visible: root.subtitle !== ""
        text: root.subtitle.toUpperCase()
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    Rectangle {
        id: badge

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -Theme.cellH * 0.1
        visible: root.badge !== ""
        width: visible ? badgeText.implicitWidth + Theme.cellW * 1.5 : 0
        height: Theme.cellH * 1.4
        radius: Theme.radius
        color: "transparent"
        border.width: Theme.borderWidth
        border.color: root.badgeColor

        Text {
            id: badgeText

            anchors.centerIn: parent
            text: root.badge
            color: root.badgeColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            renderType: Text.NativeRendering
        }
    }
}
