import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

PanelSurface {
    id: root
    implicitHeight: content.height + Theme.spaceLg * 2
    color: Theme.alpha(Theme.panelSurface, Theme.isLight ? 0.82 : 0.48)
    radius: Theme.spaceXl
    border.color: Theme.alpha(Theme.fg, 0.22)
    readonly property var providers: Object.keys(AiUsage.localStats).filter(k => (AiUsage.localStats[k].recentDays || []).length)
    readonly property var dates: providers.length ? (AiUsage.localStats[providers[0]].recentDays || []).slice(-7) : []
    readonly property real labelWidth: Math.min(Theme.cellW * 16, content.width * 0.22)
    property string detail: ""
    Column {
        id: content
        x: Theme.spaceLg; y: Theme.spaceLg
        width: parent.width - Theme.spaceLg * 2
        spacing: Theme.spaceXs
        Line { width: parent.width; text: root.detail || "ACTIVITY · LAST 7 DAYS · LOCAL CLI TOKENS"; font.pixelSize: Theme.fontCaption; color: Theme.fgDim; elide: Text.ElideRight }
        Line { visible: !root.providers.length; text: "No local activity data available"; color: Theme.fgDim }
        Repeater {
            model: root.providers
            Row {
                id: provider
                required property string modelData
                readonly property var days: (AiUsage.localStats[modelData].recentDays || []).slice(-7)
                readonly property real peak: Math.max(1, ...days.map(d => d.tokens))
                width: content.width
                spacing: Theme.spaceXs
                Line { width: root.labelWidth; text: AiUsage.providerName(provider.modelData); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
                Repeater {
                    model: provider.days
                    Rectangle {
                        id: cell
                        required property var modelData
                        width: (provider.width - root.labelWidth - Theme.spaceXs * 7) / 7
                        height: Theme.cellH
                        color: Theme.alpha(Theme.accent, 0.08 + 0.65 * modelData.tokens / provider.peak)
                        Accessible.role: Accessible.StaticText
                        Accessible.name: AiUsage.providerName(provider.modelData) + " · " + modelData.date + ": " + modelData.tokens + " tokens"
                        HoverHandler {
                            onHoveredChanged: root.detail = hovered ? cell.Accessible.name : ""
                        }
                    }
                }
            }
        }
        Row {
            visible: root.providers.length > 0
            width: parent.width
            spacing: Theme.spaceXs
            Item { width: root.labelWidth; height: Theme.cellH }
            Repeater {
                model: root.dates
                Line {
                    required property var modelData
                    width: (content.width - root.labelWidth - Theme.spaceXs * 7) / 7
                    text: modelData.date.slice(5)
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Theme.fontCaption
                    color: Theme.fgDim
                    elide: Text.ElideRight
                }
            }
        }
    }
}
