import QtQuick
import qs.Common

// Die Kopfzeile eines Popouts: Symbol und Titel, darunter gedimmt der
// Zusammenhang, rechts ein ruhiger Kurzwert.
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
//     Aufnahme. Eine leicht angehobene Flaeche trennt ihn ohne einen weiteren
//     dekorativen Rahmen vom Titel.
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

    Line {
        id: title

        anchors.left: root.icon !== "" ? mark.right : parent.left
        anchors.leftMargin: root.icon !== "" ? Theme.cellW : 0
        anchors.top: parent.top
        anchors.right: badge.left
        anchors.rightMargin: Theme.cellW
        text: root.title
        color: Theme.fgBright
        font.pixelSize: Theme.fontTitle
        font.bold: true
        elide: Text.ElideRight
    }

    Line {
        anchors.left: title.left
        anchors.top: title.bottom
        anchors.right: parent.right
        visible: root.subtitle !== ""
        text: root.subtitle.toUpperCase()
        color: Theme.fgDim
        font.pixelSize: Theme.fontCaption
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
        color: Theme.panelSurfaceRaised
        border.width: 0

        Line {
            id: badgeText

            anchors.centerIn: parent
            text: root.badge
            color: Theme.readable(root.badgeColor, Theme.bg, 4.5)
            font.pixelSize: Theme.fontCaption
        }
    }
}
