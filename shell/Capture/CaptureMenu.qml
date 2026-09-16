import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Common/MenuLayout.js" as MenuLayout
import "../Widgets/FocusScroll.js" as FocusScroll

// Omarchy's menu presentation over native capture actions. Work is scheduled
// by the service after this immediately-dismissed lazy surface is unmapped.
PanelWindow {
    id: root

    property string selectedKey: "screen"
    property bool windowMode: false
    property bool committed: false
    property var pointerPosition: null
    property real pinnedTop: -1
    property real maxRowsHeight: -1
    readonly property int selected: shownActions.findIndex(action => action.id === selectedKey)
    // Upstream uses 520px for longer capture choices. Reuse that attributed
    // width for native window titles; all other metrics use existing tokens.
    readonly property real windowWidth: Math.round(520 * Theme.menuScale)
    readonly property var actions: [
        { id: "screen", label: "Screen", key: "b", icon: Icons.camera },
        { id: "window", label: "Window", key: "f", icon: Icons.cp(0xF2D0) },
        { id: "region", label: "Region", key: "a", icon: Icons.cp(0xF125) },
        { id: "ocr", label: "Recognize text", key: "t", icon: Icons.cp(0xF0D11) },
        { id: "qr", label: "QR code", key: "q", icon: Icons.cp(0xF0432) },
        { id: "dictate", label: "Dictation", key: "d", icon: Icons.cp(0xF036C) },
        { id: "record", label: CaptureService.recording ? "Stop recording" : "Start recording", key: "v", icon: Icons.record },
        { id: "trim", label: "Trim recording", key: "c", icon: Icons.cp(0xF0190) },
        { id: "stream", label: "Streaming studio", key: "s", icon: Icons.cp(0xF0567) },
        { id: "edit", label: "Edit latest", key: "e", icon: Icons.cp(0xF03EB) },
        { id: "open", label: "Open folder", key: "o", icon: Icons.cp(0xF024B) }
    ]
    readonly property var windowActions: Compositor.windows
        .filter(window => window.title || window.app_id)
        .sort((a, b) => String(a.title || a.app_id).localeCompare(String(b.title || b.app_id)))
        .map(window => ({
            id: "window-" + window.id,
            windowId: window.id,
            label: window.title || window.app_id || "Window",
            detail: window.app_id || "",
            key: "", icon: Icons.cp(0xF2D0)
        }))
    readonly property var shownActions: windowMode ? windowActions : actions
    readonly property real rowHeight: windowMode ? Theme.menuDetailRowHeight : Theme.menuBaseRowHeight
    readonly property real rowsHeight: MenuLayout.foldedHeight(
        shownActions.length ? shownActions.map(() => rowHeight) : [rowHeight], Theme.menuRowSpacing,
        Math.min(root.height * 0.7, maxRowsHeight >= 0 ? maxRowsHeight : root.height,
            root.height - (pinnedTop >= 0 ? pinnedTop : Theme.menuScreenMargin) - Theme.menuScreenMargin
                - Theme.menuInset * 2 - Theme.menuHeaderHeight - footer.height - Theme.menuGap * 2))

    visible: Runtime.captureOpen
    screen: Compositor.focusedScreen
    color: "transparent"
    WlrLayershell.namespace: "nbshell:capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.captureOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }

    function close() {
        Runtime.captureWindowSelect = false;
        Runtime.captureOpen = false;
    }
    function revealSelection() {
        const item = rows.itemAt(selected);
        if (!item) return;
        list.contentY = FocusScroll.contentYForFocus(item.y, item.height,
            list.contentY, list.height, list.contentHeight, 0);
    }
    function focusSelection() {
        const item = rows.itemAt(selected);
        (item || backButton).forceActiveFocus(Qt.TabFocusReason);
        revealSelection();
    }
    function reconcile() {
        if (!shownActions.some(action => action.id === selectedKey))
            selectedKey = shownActions.length ? shownActions[0].id : "";
        // A live window-list replacement destroys row delegates. Restore focus
        // to the stable selected key, not an index shifted by another window.
        if (!backButton.activeFocus) focusSelection();
    }
    onShownActionsChanged: Qt.callLater(reconcile)
    onSelectedChanged: Qt.callLater(revealSelection)

    function move(delta) {
        pointerPosition = null;
        if (!shownActions.length) return;
        selectedKey = shownActions[MenuLayout.nextIndex(Math.max(0, selected), delta, shownActions.length)].id;
        focusSelection();
    }
    function selectEdge(last) {
        pointerPosition = null;
        if (!shownActions.length) return;
        selectedKey = shownActions[last ? shownActions.length - 1 : 0].id;
        focusSelection();
    }
    function openWindows() {
        if (pinnedTop < 0) { pinnedTop = box.y; maxRowsHeight = list.height; }
        pointerPosition = null;
        windowMode = true;
        selectedKey = windowActions.length ? windowActions[0].id : "";
        list.contentY = 0;
        pointerSettle.restart();
        Qt.callLater(focusSelection);
    }
    function back() {
        if (!windowMode) { close(); return; }
        pointerPosition = null;
        windowMode = false;
        selectedKey = "window";
        list.contentY = 0;
        Qt.callLater(focusSelection);
    }
    function activate(id) {
        if (committed || !Runtime.captureOpen) return;
        const action = shownActions.find(candidate => candidate.id === id);
        if (!action) return;
        if (!windowMode && action.id === "window") { openWindows(); return; }
        committed = true;
        CaptureService.schedule(windowMode ? "window" : action.id, windowMode ? action.windowId : null);
        close();
    }
    function pointTo(item, mouse) {
        const point = item.mapToItem(root.contentItem, mouse.x, mouse.y);
        if (MenuLayout.moved(pointerPosition, point)) {
            selectedKey = item.modelData.id;
            item.forceActiveFocus(Qt.MouseFocusReason);
        }
        if (pointerPosition === null || MenuLayout.moved(pointerPosition, point)) pointerPosition = point;
    }
    Component.onCompleted: {
        if (Runtime.captureWindowSelect) {
            windowMode = true;
            Runtime.captureWindowSelect = false;
            selectedKey = windowActions.length ? windowActions[0].id : "";
        }
        Qt.callLater(focusSelection);
    }
    Connections {
        target: Runtime
        function onCaptureWindowSelectChanged() {
            if (Runtime.captureWindowSelect && root.visible) {
                root.openWindows();
                Runtime.captureWindowSelect = false;
            }
        }
    }
    Timer { id: pointerSettle; interval: Application.styleHints.mouseDoubleClickInterval }

    Rectangle { anchors.fill: parent; color: Theme.menuScrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: event => { if (!event.isAutoRepeat) root.back(); event.accepted = true; }
        Keys.onLeftPressed: event => { if (!event.isAutoRepeat && root.windowMode) root.back(); event.accepted = true; }
        Keys.onRightPressed: event => {
            if (!event.isAutoRepeat && !root.windowMode && root.selectedKey === "window") root.openWindows();
            event.accepted = true;
        }
        Keys.onUpPressed: root.move(-1)
        Keys.onDownPressed: root.move(1)
        Keys.onPressed: event => {
            if (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ShiftModifier) return;
            if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                root.selectEdge(event.key === Qt.Key_End); event.accepted = true;
            } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                root.move(event.key === Qt.Key_PageUp ? -6 : 6); event.accepted = true;
            } else if (!root.windowMode && !event.isAutoRepeat) {
                const action = root.actions.find(candidate => candidate.key === event.text.toLowerCase());
                if (action) { root.activate(action.id); event.accepted = true; }
            }
        }
        MotionSurface {
            id: box
            // Match the approved menu: no zoom and no delayed dismissal.
            motionEnabled: false
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(Theme.menuScreenMargin, Math.min(root.pinnedTop >= 0 ? root.pinnedTop : Math.round((parent.height - height) / 2), parent.height - height - Theme.menuScreenMargin))
            width: Math.max(1, Math.min(root.windowMode ? root.windowWidth : Theme.menuWidth, parent.width - Theme.menuScreenMargin * 2))
            height: Math.max(1, Math.min(Theme.menuInset * 2 + Theme.menuHeaderHeight + Theme.menuGap * 2 + root.rowsHeight + footer.height, parent.height - Theme.menuScreenMargin * 2))
            color: Theme.bg
            border.width: Theme.menuBorderWidth
            border.color: Theme.fg
            clip: true
            MouseArea { anchors.fill: parent }
            ControlButton {
                id: backButton
                visible: root.windowMode
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Theme.menuInset
                width: Theme.menuHeaderHeight
                height: Theme.menuHeaderHeight
                text: "‹"
                accessibleName: "Back to capture actions"
                onTriggered: root.back()
            }
            Line {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.menuInset
                anchors.leftMargin: Theme.menuInset + (backButton.visible ? backButton.width + Theme.menuGap : 0)
                height: Theme.menuHeaderHeight
                text: root.windowMode ? "Select window…" : CaptureService.recording ? "Recording…" : "Capture…"
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
                    Line {
                        visible: root.shownActions.length === 0
                        width: parent.width
                        height: Theme.menuBaseRowHeight
                        text: "No windows available"
                        font.pixelSize: Theme.menuFontSize
                        color: Theme.networkSecondary
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                    }
                    Repeater {
                        id: rows
                        model: root.shownActions
                        InteractiveSurface {
                            id: row
                            required property var modelData
                            readonly property bool selected: modelData.id === root.selectedKey
                            width: column.width
                            height: root.rowHeight
                            color: selected ? Theme.menuSelection : "transparent"
                            radius: Theme.radius
                            border.width: activeFocus ? Theme.borderWidth : 0
                            border.color: Theme.focusBorder
                            accessibleName: modelData.label
                            accessibleRole: Accessible.MenuItem
                            accessibleDescription: root.windowMode ? "Capture this window; " + modelData.detail
                                : "Capture action; shortcut " + modelData.key.toUpperCase()
                            accessibleSelected: selected
                            onActiveFocusChanged: if (activeFocus) { root.selectedKey = modelData.id; Qt.callLater(root.revealSelection); }
                            onTriggered: root.activate(modelData.id)
                            Line {
                                id: icon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.menuRowInset
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.menuIconSlot
                                text: row.modelData.icon
                                horizontalAlignment: Text.AlignHCenter
                                color: row.selected ? Theme.menuSelectedText : Theme.fg
                                font.pixelSize: Theme.menuIconSize
                            }
                            Column {
                                anchors.left: icon.right
                                anchors.right: shortcut.left
                                anchors.leftMargin: Theme.menuGap
                                anchors.rightMargin: Theme.menuGap
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.menuRowSpacing
                                Line {
                                    width: parent.width
                                    text: row.modelData.label
                                    font.pixelSize: Theme.menuFontSize
                                    color: row.selected ? Theme.menuSelectedText : Theme.fg
                                    elide: Text.ElideRight
                                }
                                Line {
                                    width: parent.width
                                    visible: root.windowMode
                                    text: row.modelData.detail || ""
                                    font.pixelSize: Theme.menuDetailFontSize
                                    color: Theme.networkSecondary
                                    elide: Text.ElideRight
                                }
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
                                    if (pointerSettle.running) return;
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
                text: root.windowMode ? "↑↓ select · Enter capture · Esc back" : "↑↓ select · Enter · Esc closes"
                color: Theme.networkSecondary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }
    }
}
