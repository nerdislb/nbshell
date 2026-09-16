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
        PanelHead { rowWidth: parent.width; title: "GIT PROJECTS"; subtitle: "Local / Read only" }
        Line { visible: !WorkState.paths.length; width: parent.width; text: "No project paths supplied. Pin one with nbshell work project /path"; wrapMode: Text.Wrap; color: Theme.fgDim }
        Line { visible: WorkState.projectError !== ""; width: parent.width; text: WorkState.projectError; wrapMode: Text.Wrap; color: Theme.yellow }
        Repeater {
            model: WorkState.paths
            Column {
                required property string modelData
                readonly property var git: WorkState.projects[modelData] || ({})
                width: content.width
                spacing: Theme.spaceXs
                Line { width: parent.width; text: parent.modelData.split("/").filter(Boolean).pop() || "/"; color: Theme.fgBright; font.bold: true; elide: Text.ElideRight }
                Line { width: parent.width; text: parent.git.error || (parent.git.branch ? parent.git.branch + " · " + parent.git.changed + " changes" + (parent.git.conflicts ? " · " + parent.git.conflicts + " conflicts" : "") : "Checking Git…"); wrapMode: Text.Wrap; color: parent.git.error || parent.git.conflicts ? Theme.yellow : Theme.green }
                Line { width: parent.width; text: parent.modelData; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideMiddle }
                Rule { width: parent.width }
            }
        }
    }
}
