import QtQuick
import qs.Common
import qs.Widgets

InteractiveSurface {
    id: root

    property string label: ""
    property string detail: ""
    property string glyph: ""
    property color tone: Theme.accent
    property var run: null
    property var rightRun: null
    property string rightLabel: ""
    property bool centered: false
    readonly property alias secondaryButton: rightHint

    interactive: run !== null
    accessibleName: label
    accessibleDescription: detail
    accessiblePressed: tap.pressed
    onTriggered: if (run) run()

    width: Theme.cellW * 21
    height: Theme.cellH * 3.2
    radius: Theme.radius
    color: Theme.controlFill(hover.hovered || visualFocus, false, tap.pressed)
    border.width: Theme.borderWidth
    border.color: visualFocus ? Theme.focusBorder
        : (hover.hovered ? root.tone : Theme.controlBorder(false, false, false))

    function triggerSecondary() {
        if (root.enabled && root.rightRun)
            root.rightRun();
    }

    function pointerInsideSecondary(position) {
        if (!rightHint.visible)
            return false;
        const topLeft = rightHint.mapToItem(root, 0, 0);
        return position.x >= topLeft.x
            && position.x <= topLeft.x + rightHint.width
            && position.y >= topLeft.y
            && position.y <= topLeft.y + rightHint.height;
    }

    function activateFromPointer(position, button) {
        if (root.pointerInsideSecondary(position))
            return;
        if (button === Qt.RightButton)
            root.triggerSecondary();
        else if (button === Qt.LeftButton)
            root.activate();
    }

    Line {
        visible: !root.centered
        anchors.left: parent.left
        anchors.leftMargin: Theme.cellW
        anchors.top: parent.top
        anchors.topMargin: Theme.cellH * 0.55
        text: root.glyph + (root.glyph !== "" ? "  " : "") + root.label
        color: root.tone
        font.pixelSize: Theme.fontBody
        font.bold: true
    }

    Line {
        visible: !root.centered
        anchors.left: parent.left
        anchors.leftMargin: Theme.cellW
        anchors.right: rightHint.left
        anchors.rightMargin: Theme.cellW * 0.5
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.cellH * 0.45
        text: root.detail
        color: Theme.fgDim
        font.pixelSize: Theme.fontCaption
        elide: Text.ElideRight
    }

    ActionButton {
        id: rightHint
        visible: !root.centered && root.rightRun !== null
        anchors.right: parent.right
        anchors.rightMargin: Theme.cellW * 0.55
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.cellH * 0.2
        text: "R"
        compact: true
        accessibleName: root.rightLabel !== "" ? root.rightLabel : root.label + " secondary action"
        onTriggered: root.triggerSecondary()
        onRightTriggered: root.triggerSecondary()
    }

    Column {
        visible: root.centered
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spaceXs
        Line {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph + (root.glyph !== "" ? "  " : "") + root.label
            color: root.tone
            font.pixelSize: Theme.fontBody
            font.bold: true
        }
        Line {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.detail
            color: Theme.fgDim
            font.pixelSize: Theme.fontCaption
            elide: Text.ElideRight
        }
    }

    HoverHandler {
        id: hover
        enabled: root.enabled && (root.run !== null || root.rightRun !== null)
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: tap
        enabled: root.enabled && (root.run !== null || root.rightRun !== null)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => root.activateFromPointer(point.position, button)
    }
}
