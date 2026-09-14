import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Column {
    id: root
    readonly property var live: WorkState.rows.filter(r => WorkState.rank(r) <= 1)
    spacing: Theme.spaceLg
    PanelSurface {
        width: parent.width
        height: liveContent.height + Theme.panelPadding * 2
        color: Theme.alpha(Theme.panelSurface, Theme.isLight ? 0.82 : 0.48)
        radius: Theme.spaceXl
        border.color: Theme.alpha(Theme.fg, 0.22)
        Column {
            id: liveContent
            x: Theme.panelPadding; y: Theme.panelPadding
            width: parent.width - Theme.panelPadding * 2
            spacing: Theme.spaceSm
            Line { width: parent.width; text: "LIVE AI SESSIONS  ·  " + root.live.length + " active"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
            Line { width: parent.width; visible: text !== ""; text: [Agents.monitorError, Agents.openclaw.error].filter(Boolean).join(" · "); wrapMode: Text.Wrap; color: Theme.yellow; font.pixelSize: Theme.fontCaption }
            Line { visible: !root.live.length; text: "No active sessions"; color: Theme.fgDim }
            Grid {
                id: cards
                width: parent.width
                columns: Math.max(1, Math.min(4, Math.floor(width / (Theme.cellW * 38))))
                spacing: Theme.spaceSm
                Repeater {
                    model: root.live
                    InteractiveSurface {
                        id: card
                        required property var modelData
                        width: (cards.width - cards.spacing * (cards.columns - 1)) / cards.columns
                        height: Math.max(Theme.cellH * 13, cardDetails.height + Theme.spaceLg * 2)
                        radius: Theme.spaceXl
                        color: Theme.alpha(Theme.panelSurfaceRaised, 0.35)
                        border.width: Theme.borderWidth
                        border.color: visualFocus ? Theme.focusBorder : Theme.alpha(Theme.accent, 0.35)
                        accessibleName: modelData.title || modelData.name || "Session"
                        accessibleDescription: WorkState.statusText(modelData)
                        onTriggered: WorkState.openSession(modelData)
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { card.forceActiveFocus(Qt.MouseFocusReason); card.activate(); } }
                        Column {
                            id: cardDetails
                            x: Theme.spaceLg; y: Theme.spaceLg
                            width: parent.width - Theme.spaceLg * 2
                            spacing: Theme.spaceSm
                            Line { width: parent.width; text: "● " + (card.modelData.backend === "openclaw" ? "OpenClaw" : "Herdr"); color: Theme.accent; elide: Text.ElideRight }
                            Line { width: parent.width; text: card.modelData.title || card.modelData.name || "Session"; color: Theme.fgBright; font.bold: true; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
                            Line { width: parent.width; text: card.modelData.progress || WorkState.statusText(card.modelData); color: Theme.fg; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
                            Line { width: parent.width; text: card.modelData.project || "Project not provided"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideMiddle }
                            Line { width: parent.width; visible: WorkState.moduleEnabled("git") && !!card.modelData.project; text: WorkState.projectText(card.modelData); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideMiddle }
                            Line { width: parent.width; text: WorkState.statusText(card.modelData); color: WorkState.rank(card.modelData) === 0 ? Theme.yellow : Theme.green; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }
    }
}
