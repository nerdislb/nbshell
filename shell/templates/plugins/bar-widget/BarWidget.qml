import QtQuick
import qs.Common
import qs.Widgets

Cell {
    id: root

    label: "NEW"
    icon: Icons.palette
    text: ""
    color: Theme.text
    interactive: true

    onClicked: active = !active
}
