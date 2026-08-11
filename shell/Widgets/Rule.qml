import QtQuick
import qs.Common

// Eine Haarlinie, wahlweise mit Ueberschrift darunter -- das `---` einer
// Manpage.
//
// Bisher trennten die Popouts ihre Abschnitte nur durch Abstand. Das ist bei
// zwei Abschnitten genug und bei fuenf nicht mehr: man sieht, dass da Luft
// ist, aber nicht, dass etwas Neues anfaengt. Omarchy 4 zieht in seinen
// Panels eine Linie und setzt die Ueberschrift darunter; genau das ist auch
// im Terminal die uebliche Geste.
//
//   Rule { rowWidth: panel.rowWidth; label: "TEMPERATUR" }
//
// Ohne `label` bleibt nur die Linie -- fuer den Fall, dass die Ueberschrift
// schon im Inhalt steht.
Item {
    id: root

    property real rowWidth: 0
    property string label: ""

    // Wie viel Luft ueber der Linie liegt. Unter ihr sitzt die Ueberschrift,
    // die ihren Abstand selbst mitbringt.
    property real lead: Theme.cellH * 0.5

    width: root.rowWidth
    height: root.lead + Theme.borderWidth + (root.label !== "" ? Theme.cellH * 1.3 : Theme.cellH * 0.3)

    Rectangle {
        id: line

        anchors.left: parent.left
        anchors.right: parent.right
        y: root.lead
        height: Theme.borderWidth
        color: Theme.muted
    }

    Line {
        anchors.left: parent.left
        anchors.top: line.bottom
        anchors.topMargin: Theme.cellH * 0.3
        visible: root.label !== ""
        text: root.label
        color: Theme.fgDim
    }
}
