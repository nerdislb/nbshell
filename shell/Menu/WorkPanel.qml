import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root
    property bool active: false
    signal openSession(var row)
    readonly property var rows: WorkState.rows
    readonly property var projects: WorkState.projects
    readonly property string projectError: WorkState.projectError
    function rank(row) { return WorkState.rank(row); }
    function statusText(row) { return WorkState.statusText(row); }
    function projectText(row) { return WorkState.projectText(row); }
    onActiveChanged: WorkState.dashboardActive = active
    Component.onCompleted: WorkState.dashboardActive = active
    Component.onDestruction: WorkState.dashboardActive = false
    Column {
        anchors.fill: parent
        anchors.margins: Theme.spaceSm
        spacing: Theme.spaceSm
        Line {
            width: parent.width
            text: "WORK  ·  " + root.rows.filter(r => root.rank(r) === 0).length + " need you  ·  " + root.rows.filter(r => r.status === "working").length + " working"
            color: Theme.fgBright
            elide: Text.ElideRight
        }
        Line {
            width: parent.width
            text: [Agents.monitorError, Agents.openclaw.error, root.projectError].filter(Boolean).join(" · ") || "Herdr + OpenClaw · Select a session to open it · Git refreshes every 15s"
            color: Agents.monitorError || Agents.openclaw.error || root.projectError ? Theme.yellow : Theme.fgDim
            elide: Text.ElideRight
        }
        Flickable {
            id: scroll
            width: parent.width
            height: parent.height - y
            clip: true
            contentWidth: width
            contentHeight: entries.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: entries
                width: scroll.width
                spacing: Theme.spaceXs
                Line { visible: !root.rows.length; text: "No sessions available"; color: Theme.fgDim }
                Repeater {
                    model: root.rows
                    InteractiveSurface {
                        id: entry
                        required property var modelData
                        width: entries.width
                        height: content.height + Theme.spaceSm * 2
                        accessibleName: modelData.title || modelData.name || "Session"
                        accessibleDescription: root.statusText(modelData) + " · " + root.projectText(modelData)
                        onTriggered: root.openSession(modelData)
                        onActiveFocusChanged: if (activeFocus) scroll.contentY = Math.max(0, Math.min(y, Math.max(scroll.contentY, y + height - scroll.height)))
                        color: Theme.controlFill(hovered || visualFocus, false, false)
                        border.width: Theme.borderWidth
                        border.color: visualFocus ? Theme.focusBorder : Theme.panelBorder
                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        readonly property bool hovered: hover.hovered
                        TapHandler { onTapped: entry.activate() }
                        Column {
                            id: content
                            x: Theme.spaceSm
                            y: Theme.spaceSm
                            width: parent.width - Theme.spaceSm * 2
                            spacing: Theme.spaceXs
                            Line {
                                width: parent.width
                                text: (entry.modelData.backend === "openclaw" ? "OPENCLAW" : "HERDR") + " · " + root.statusText(entry.modelData) + " · " + (entry.modelData.title || entry.modelData.name || "Session")
                                color: root.rank(entry.modelData) === 0 ? Theme.yellow : entry.modelData.status === "working" ? Theme.green : Theme.fg
                                elide: Text.ElideRight
                            }
                            Line {
                                width: parent.width
                                text: entry.modelData.progress || (entry.modelData.backend === "openclaw" ? entry.modelData.id : entry.modelData.name || "")
                                color: Theme.fgDim
                                elide: Text.ElideRight
                            }
                            Line {
                                width: parent.width
                                text: root.projectText(entry.modelData)
                                color: (root.projects[entry.modelData.project] || {}).conflicts ? Theme.red : Theme.fgDim
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }
                Line {
                    visible: Number(Agents.openclaw.detailTotal || 0) > (Agents.openclaw.items || []).length
                    text: "Showing the 40 most recent OpenClaw sessions"
                    color: Theme.fgDim
                }
            }
        }
    }
}
