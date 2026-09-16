import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
Column {
    id: root
    property bool showAll: false
    readonly property var recent: WorkState.rows.filter(r => WorkState.rank(r) > 1)
    PanelSurface {
        width: parent.width
        height: recentContent.height + Theme.panelPadding * 2
        color: Theme.alpha(Theme.panelSurface, Theme.isLight ? 0.82 : 0.48)
        radius: Theme.radius
        border.color: Theme.alpha(Theme.fg, 0.22)
        Column {
            id: recentContent
            x: Theme.panelPadding; y: Theme.panelPadding
            width: parent.width - Theme.panelPadding * 2
            spacing: Theme.spaceXs
            Line { width: parent.width; text: "RECENT SESSIONS  ·  " + root.recent.length + " idle"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
            Line { visible: !root.recent.length; text: "No recent sessions"; color: Theme.fgDim }
            Repeater {
                model: root.showAll ? root.recent : root.recent.slice(0, 10)
                InteractiveSurface {
                    id: row
                    required property var modelData
                    width: recentContent.width
                    height: Theme.controlHeight
                    radius: Theme.radius
                    color: Theme.alpha(Theme.panelSurfaceRaised, 0.25)
                    border.width: Theme.borderWidth
                    border.color: visualFocus ? Theme.focusBorder : Theme.alpha(Theme.fg, 0.12)
                    accessibleName: modelData.title || modelData.name || "Session"
                    onTriggered: WorkState.openSession(modelData)
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { row.forceActiveFocus(Qt.MouseFocusReason); row.activate(); } }
                    Line { x: Theme.spaceLg; anchors.verticalCenter: parent.verticalCenter; width: Theme.cellW * 10; text: row.modelData.backend === "openclaw" ? "OpenClaw" : "Herdr"; color: Theme.accent; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
                    Line { x: Theme.cellW * 12; anchors.verticalCenter: parent.verticalCenter; width: Math.max(1, parent.width - x - Theme.spaceLg); text: row.modelData.title || row.modelData.name || "Session"; color: Theme.fg; elide: Text.ElideRight }
                }
            }
            ControlButton { visible: root.recent.length > 10; text: root.showAll ? "Show fewer sessions" : "Show all " + WorkState.rows.length + " sessions"; onTriggered: root.showAll = !root.showAll }
        }
    }
}
