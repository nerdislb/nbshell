import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
    id: root

    shown: ZenPip.active
    interactive: true
    icon: Icons.play
    label: "PIP"
    text: ""
    color: Theme.cyan

    onClicked: ZenPip.run("size")
    onWheel: delta => ZenPip.run(delta > 0 ? "size" : "corner")

    popout: Component {
        Column {
            property var closePopout: null
            readonly property real rowWidth: 36 * Theme.cellW
            spacing: Theme.cellH * 0.4

            component Action: Line {
                signal triggered
                color: hover.hovered ? Theme.fg : Theme.fgDim
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: parent.triggered() }
            }

            PanelHead {
                rowWidth: parent.rowWidth
                icon: Icons.play
                title: "ZEN PICTURE-IN-PICTURE"
                subtitle: ZenPip.cornerName
                badge: ZenPip.sizeName
                badgeColor: Theme.cyan
            }

            Rule { rowWidth: parent.rowWidth }

            Row {
                spacing: Theme.cellW * 2
                Action { text: "[ groesse ]"; onTriggered: ZenPip.run("size") }
                Action { text: "[ ecke ]"; onTriggered: ZenPip.run("corner") }
                Action { text: "[ fokus ]"; onTriggered: ZenPip.run("focus") }
                Action { text: "[ schliessen ]"; color: Theme.red; onTriggered: ZenPip.run("close") }
            }

            Line {
                width: parent.rowWidth
                text: "Frei bewegen: Mod + linke Maustaste"
                color: Theme.muted
            }
        }
    }
}
