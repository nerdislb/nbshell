import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "Dates.js" as Dates

// Calendar-specific event tile: title always precedes secondary time metadata.
InteractiveSurface {
    id: root
    required property var event
    property color tone: Theme.accent
    property bool compact: false
    implicitHeight: compact ? Theme.cellH * 2 : Theme.cellH * 3
    accessibleName: event.title || "Untitled event"
    accessibleDescription: time.text + (event.blocked ? ". View only" : "")
    color: Theme.controlFill(hover.hovered || visualFocus, false, tap.pressed)
    border.width: visualFocus ? Theme.borderWidth : 0
    border.color: Theme.focusBorder
    Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: Theme.borderWidth; color: Theme.readable(root.tone, root.color, 3) }
    Column {
        anchors { fill: parent; margins: Theme.spaceXs }
        spacing: 0
        Line { width: parent.width; text: root.event.title || "Untitled event"; elide: Text.ElideRight; font.pixelSize: root.compact ? Theme.fontCaption : Theme.fontBody }
        Line { id: time; width: parent.width; text: root.event.allDay ? "All day" : Dates.date(root.event.start).toLocaleTimeString(Qt.locale(), "HH:mm"); color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: { root.forceActiveFocus(); root.activate(); } }
}
