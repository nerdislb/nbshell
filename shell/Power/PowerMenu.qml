import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Common/MenuLayout.js" as MenuLayout
import "../Widgets/FocusScroll.js" as FocusScroll

// Omarchy System-menu presentation; native session actions and confirmation.
PanelWindow {
    id: root

    property string selectedKey: "lock"
    property string confirmKey: ""
    property bool committed: false
    property var afterClose: null
    property var pointerPosition: null
    readonly property var actions: Session.actions
    readonly property int selected: actions.findIndex(action => action.id === selectedKey)
    readonly property real rowsHeight: MenuLayout.foldedHeight(
        actions.map(() => Theme.menuBaseRowHeight), Theme.menuRowSpacing,
        Math.max(0, root.height - Theme.menuScreenMargin * 2 - Theme.menuInset * 2
            - Theme.menuHeaderHeight - footer.height - Theme.menuGap * 2))

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    WlrLayershell.namespace: "nbshell:power"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.powerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }

    function disarm() {
        confirmKey = "";
        confirmReset.stop();
    }
    function close() {
        disarm();
        Runtime.powerOpen = false;
    }
    function requestClose(done) {
        disarm();
        box.dismiss(() => {
            const next = root.afterClose;
            root.afterClose = null;
            if (!Runtime.powerOpen && next) next();
            done();
        });
    }
    function requestOpen() {
        afterClose = null;
        committed = false;
        disarm();
        box.enter();
        Qt.callLater(focusSelection);
    }
    function revealSelection() {
        const item = rows.itemAt(selected);
        if (item) list.contentY = FocusScroll.contentYForFocus(item.y, item.height,
            list.contentY, list.height, list.contentHeight, 0);
    }
    function focusSelection() {
        const item = rows.itemAt(selected);
        if (item) item.forceActiveFocus(Qt.TabFocusReason);
        revealSelection();
    }
    function select(id) {
        if (selectedKey !== id) disarm();
        selectedKey = id;
    }
    function move(delta) {
        pointerPosition = null;
        disarm();
        if (!actions.length) return;
        select(actions[MenuLayout.nextIndex(Math.max(0, selected), delta, actions.length)].id);
        focusSelection();
    }
    function selectEdge(last) {
        pointerPosition = null;
        disarm();
        if (!actions.length) return;
        select(actions[last ? actions.length - 1 : 0].id);
        focusSelection();
    }
    function activate(id) {
        if (committed || !Runtime.powerOpen) return;
        const action = actions.find(candidate => candidate.id === id);
        if (!action) return;
        select(id);
        focusSelection();
        if (confirmKey !== id) {
            confirmKey = id;
            confirmReset.restart();
            return;
        }
        committed = true;
        afterClose = () => Session.run(action.id);
        close();
    }
    function shortcut(event) {
        if (event.isAutoRepeat || (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ShiftModifier)) return;
        const action = actions.find(candidate => candidate.key === event.text.toLowerCase());
        if (action) { activate(action.id); event.accepted = true; }
    }
    function pointTo(item, mouse) {
        const point = item.mapToItem(root.contentItem, mouse.x, mouse.y);
        if (MenuLayout.moved(pointerPosition, point)) {
            select(item.modelData.id);
            item.forceActiveFocus(Qt.MouseFocusReason);
        }
        if (pointerPosition === null || MenuLayout.moved(pointerPosition, point)) pointerPosition = point;
    }
    function iconFor(id) {
        // Pinned Omarchy system.* icons; no backend or action substitution.
        const icons = {lock: 0xF023, logout: 0xF0343, suspend: 0xF04B2,
            hibernate: 0xF0901, reboot: 0xF0709, poweroff: 0xF0425};
        return Icons.cp(icons[id] || 0xF011);
    }
    onSelectedChanged: Qt.callLater(revealSelection)
    Component.onCompleted: Qt.callLater(focusSelection)

    Rectangle { anchors.fill: parent; color: Theme.menuScrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
        Keys.onPressed: event => {
            if (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ShiftModifier) return;
            if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                root.selectEdge(event.key === Qt.Key_End); event.accepted = true;
            } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                root.move(event.key === Qt.Key_PageUp ? -5 : 5); event.accepted = true;
            } else root.shortcut(event);
        }
        MotionSurface {
            id: box
            motionEnabled: false
            anchors.centerIn: parent
            width: Math.max(1, Math.min(Theme.menuWidth, parent.width - Theme.menuScreenMargin * 2))
            height: Math.max(1, Math.min(Theme.menuInset * 2 + Theme.menuHeaderHeight
                + Theme.menuGap * 2 + root.rowsHeight + footer.height, parent.height - Theme.menuScreenMargin * 2))
            color: Theme.bg
            border.width: Theme.menuBorderWidth
            border.color: Theme.fg
            clip: true
            MouseArea { anchors.fill: parent }
            Line {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.menuInset
                height: Theme.menuHeaderHeight
                text: "Session…"
                color: Theme.networkSecondary
                font.pixelSize: Theme.menuFontSize
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            Flickable {
                id: list
                anchors.top: header.bottom
                anchors.topMargin: Theme.menuGap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.leftMargin: Theme.menuInset
                anchors.rightMargin: Theme.menuInset
                anchors.bottomMargin: Theme.menuGap
                contentHeight: column.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onHeightChanged: Qt.callLater(root.revealSelection)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: column
                    width: list.width
                    spacing: Theme.menuRowSpacing
                    Repeater {
                        id: rows
                        model: root.actions
                        InteractiveSurface {
                            id: row
                            required property var modelData
                            readonly property bool selected: modelData.id === root.selectedKey
                            readonly property bool armed: modelData.id === root.confirmKey
                            width: column.width
                            height: Theme.menuBaseRowHeight
                            color: selected ? Theme.menuSelection : "transparent"
                            radius: Theme.radius
                            border.width: activeFocus ? Theme.borderWidth : 0
                            border.color: Theme.focusBorder
                            accessibleName: (armed ? "Confirm " : "") + modelData.label
                            accessibleRole: Accessible.MenuItem
                            accessibleDescription: armed ? "Activate again to " + modelData.label.toLowerCase() + "; Escape cancels"
                                : "Requires confirmation; shortcut " + modelData.key.toUpperCase()
                            accessibleSelected: selected
                            onActiveFocusChanged: if (activeFocus) { root.select(modelData.id); Qt.callLater(root.revealSelection); }
                            onTriggered: root.activate(modelData.id)
                            Line {
                                id: icon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.menuRowInset
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.menuIconSlot
                                text: root.iconFor(row.modelData.id)
                                horizontalAlignment: Text.AlignHCenter
                                color: row.selected ? Theme.menuSelectedText : Theme.fg
                                font.pixelSize: Theme.menuIconSize
                            }
                            Line {
                                anchors.left: icon.right
                                anchors.right: shortcut.left
                                anchors.leftMargin: Theme.menuGap
                                anchors.rightMargin: Theme.menuGap
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.accessibleName
                                font.pixelSize: Theme.menuFontSize
                                color: row.selected ? Theme.menuSelectedText : Theme.fg
                                elide: Text.ElideRight
                            }
                            Line {
                                id: shortcut
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.menuRowInset
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.menuTrailWidth
                                text: row.modelData.key.toUpperCase()
                                color: Theme.networkSecondary
                                font.pixelSize: Theme.menuDetailFontSize
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.pointTo(row, {x: mouseX, y: mouseY})
                                onPositionChanged: mouse => root.pointTo(row, mouse)
                                onClicked: {
                                    row.forceActiveFocus(Qt.MouseFocusReason);
                                    row.activate();
                                }
                            }
                        }
                    }
                }
            }
            Line {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.menuInset
                // Reserve both lines so arming cannot move rows under the pointer.
                height: Math.max(idleHelp.implicitHeight, armedHelp.implicitHeight)
                text: root.confirmKey ? armedHelp.text : idleHelp.text
                color: Theme.networkSecondary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
                Line { id: idleHelp; visible: false; width: parent.width; font.pixelSize: Theme.fontCaption; wrapMode: Text.WordWrap; text: "↑↓ select · Enter arms · Esc closes" }
                Line { id: armedHelp; visible: false; width: parent.width; font.pixelSize: Theme.fontCaption; wrapMode: Text.WordWrap; text: "Activate again to confirm · Esc cancels" }
            }
        }
    }
    Timer {
        id: confirmReset
        // Existing confirmation expiry, not an animation duration.
        interval: 3500
        onTriggered: root.confirmKey = ""
    }
}
