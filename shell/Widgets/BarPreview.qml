import QtQuick
import qs.Common

// Shared compact hover card for bar modules. Full click popouts remain free to
// be richer; previews use one width, header rhythm, and content spacing.
Column {
    id: root

    property var closePopout: null
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string badge: ""
    property color badgeColor: Theme.fgDim
    property int widthCells: 40
    readonly property real rowWidth: widthCells * Theme.cellW

    property alias content: body.data

    width: rowWidth
    spacing: Theme.cellH * 0.3

    PanelHead {
        rowWidth: root.rowWidth
        icon: root.icon
        title: root.title
        subtitle: root.subtitle
        badge: root.badge
        badgeColor: root.badgeColor
    }

    Column {
        id: body
        width: root.rowWidth
        spacing: Theme.cellH * 0.25
    }
}
