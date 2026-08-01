import QtQuick
import qs.Common

// Trennstrich zwischen zwei Gruppen -- ein Zeichen breit, wie in einer
// Statuszeile.
Item {
    property bool shown: true

    implicitWidth: Theme.cellW
    implicitHeight: Theme.barHeight - Theme.padY

    Rectangle {
        anchors.centerIn: parent
        width: Math.max(1, Theme.borderWidth)
        height: parent.height * 0.6
        color: Theme.muted
    }
}
