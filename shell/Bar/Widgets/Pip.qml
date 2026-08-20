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
                ActionButton { text: "Size"; compact: true; onTriggered: ZenPip.run("size") }
                ActionButton { text: "Corner"; compact: true; onTriggered: ZenPip.run("corner") }
                ActionButton { text: "Focus"; tone: "primary"; compact: true; onTriggered: ZenPip.run("focus") }
                ActionButton { text: "Close"; tone: "danger"; compact: true; onTriggered: ZenPip.run("close") }
            }

            Line {
                width: parent.rowWidth
                text: "Move freely: Mod + left mouse button"
                color: Theme.muted
            }
        }
    }
}
