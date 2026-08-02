import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Arbeitsflaechen des Bildschirms, auf dem die Zelle steht.
//
// Eine Zelle mit eigenem Inhalt statt Text: die einzelnen Nummern muessen
// anklickbar sein und eigene Farben haben. Mausrad blaettert durch.
Cell {
    id: root

    property string output: ""

    readonly property var list: Niri.workspacesForOutput(output)

    custom: true
    interactive: true

    onWheel: delta => {
        const items = root.list;
        const current = items.findIndex(w => w.is_active);
        if (current < 0)
            return;
        const next = delta > 0 ? current - 1 : current + 1;
        if (next >= 0 && next < items.length)
            Niri.focusWorkspace(items[next].idx);
    }

    Row {
        spacing: Theme.cellW

        Repeater {
            model: root.list

            Text {
                required property var modelData

                text: modelData.name ? modelData.name : String(modelData.idx)
                color: modelData.is_active ? Theme.accent : (modelData.is_urgent ? Theme.red : Theme.fgDim)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.underline: modelData.is_active
                renderType: Text.NativeRendering

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Theme.cellW / 2
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Niri.focusWorkspace(parent.modelData.idx)
                }
            }
        }
    }
}
