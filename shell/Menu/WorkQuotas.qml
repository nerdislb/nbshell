import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

PanelSurface {
    implicitHeight: content.height + Theme.panelPadding * 2
    color: Theme.alpha(Theme.panelSurface, Theme.isLight ? 0.82 : 0.48)
    radius: Theme.radius
    border.color: Theme.alpha(Theme.fg, 0.22)
    Column {
        id: content
        x: Theme.panelPadding; y: Theme.panelPadding
        width: parent.width - Theme.panelPadding * 2
        spacing: Theme.spaceSm
        Line { width: parent.width; text: "USAGE & LIMITS"; font.pixelSize: Theme.fontCaption; color: Theme.fgDim }
        Line { width: parent.width; visible: !AiUsage.list.length; text: "Quota data unavailable"; wrapMode: Text.Wrap; color: Theme.fgDim }
        Repeater {
            model: AiUsage.list
            Column {
                required property var modelData
                width: content.width
                spacing: Theme.spaceXs
                Line { width: parent.width; text: parent.modelData.name; font.bold: true; color: Theme.fgBright; elide: Text.ElideRight }
                Line { width: parent.width; visible: !(parent.modelData.limits || []).length; text: "No quota data"; color: Theme.fgDim }
                Repeater {
                    model: parent.modelData.limits || []
                    Column {
                        required property var modelData
                        width: content.width
                        spacing: Theme.spaceXs
                        Line { width: parent.width; text: (parent.modelData.label || "Usage") + " · " + parent.modelData.percent + "% · " + AiUsage.untilReset(parent.modelData); elide: Text.ElideRight; font.pixelSize: Theme.fontCaption; color: parent.modelData.percent >= 90 ? Theme.yellow : Theme.fg }
                        LevelBar { value: parent.modelData.percent; interactive: false; cells: Math.max(1, Math.floor(content.width / (Theme.cellW * 1.2))); fillColor: value >= 90 ? Theme.yellow : Theme.accent }
                    }
                }
                Rule { width: parent.width }
            }
        }
    }
}
