import QtQuick
import qs.Common

Item {
    id: root

    property string text: ""
    property string detail: ""

    implicitWidth: Theme.cellW * 24
    implicitHeight: Theme.controlHeight

    Line {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.text.toUpperCase()
        color: Theme.fgDim
        font.pixelSize: Theme.fontCaption
        font.bold: true
        font.letterSpacing: 0.6
    }

    Line {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.detail
        color: Theme.muted
        font.pixelSize: Theme.fontCaption
    }
}
