import QtQuick
import Quickshell
import qs.Common

// Each level retains its opener: child handles belong to the parent model.
Column {
    id: root
    property var handle: null
    property var dismiss: null
    property real rowWidth: 32 * Theme.cellW
    property var stack: []
    readonly property var currentChildren: stack.length ? stack[stack.length - 1].opener.children.values : opener.children.values
    readonly property Item initialFocusItem: stack.length ? backButton : firstFocusableItem()
    spacing: Theme.spaceXs

    function firstFocusableItem(preferred) {
        for (let i = 0; i < entries.count; ++i) {
            const row = entries.itemAt(i);
            if (row?.visible && row.enabled && row.interactive && (!preferred || row.modelData === preferred))
                return row;
        }
        return null;
    }
    function focusEntry(preferred) {
        Qt.callLater(() => (firstFocusableItem(preferred) || initialFocusItem)?.forceActiveFocus(Qt.TabFocusReason));
    }
    function trimStack(length) {
        const old = stack;
        stack = old.slice(0, length);
        for (let i = old.length - 1; i >= length; --i)
            old[i].opener.destroy();
    }
    function validateStack() {
        for (let i = 0; i < stack.length; ++i) {
            const parent = i ? stack[i - 1].opener : opener;
            if (parent.children.values.indexOf(stack[i].entry) < 0) {
                trimStack(i);
                focusEntry();
                return;
            }
        }
    }
    function enter(entry) {
        if (!entry || !entry.enabled || !entry.hasChildren)
            return;
        const child = openerComponent.createObject(root, {menu: entry});
        if (!child)
            return;
        stack = stack.concat([{opener: child, entry: entry, title: entry.text}]);
        settle.restart();
        Qt.callLater(() => backButton.forceActiveFocus(Qt.TabFocusReason));
    }
    function leave() {
        if (!stack.length)
            return;
        const entry = stack[stack.length - 1].entry;
        trimStack(stack.length - 1);
        settle.restart();
        focusEntry(entry);
    }
    function moveFocus(item, forward) {
        const next = item.nextItemInFocusChain(forward);
        if (next && next !== item)
            next.forceActiveFocus(Qt.TabFocusReason);
    }
    onHandleChanged: trimStack(0)

    // Prevent the second tap of a double-click hitting a newly revealed action.
    Timer { id: settle; interval: Application.styleHints.mouseDoubleClickInterval }
    QsMenuOpener {
        id: opener
        menu: root.handle
        onChildrenChanged: Qt.callLater(root.validateStack)
    }
    Connections {
        target: opener.children
        function onValuesChanged() { Qt.callLater(root.validateStack); }
    }
    Component {
        id: openerComponent
        QsMenuOpener {
            id: levelOpener
            onChildrenChanged: Qt.callLater(root.validateStack)
            property var observer: Connections {
                target: levelOpener.children
                function onValuesChanged() { Qt.callLater(root.validateStack); }
            }
        }
    }
    ActionButton {
        id: backButton
        visible: root.stack.length > 0
        width: root.rowWidth
        text: "‹ Back"
        compact: true
        onTriggered: root.leave()
        Keys.onLeftPressed: root.leave()
        Keys.onDownPressed: root.focusEntry()
    }
    Line {
        visible: root.stack.length > 0
        width: root.rowWidth
        text: root.stack.length ? root.stack[root.stack.length - 1].title : ""
        elide: Text.ElideRight
        color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
    }
    Line {
        visible: root.currentChildren.length === 0
        width: root.rowWidth
        text: "No menu items"
        color: Theme.readable(Theme.fgDim, Theme.bg, 4.5)
    }
    Repeater {
        id: entries
        model: root.currentChildren
        InteractiveSurface {
            id: menuRow
            required property var modelData
            width: root.rowWidth
            height: modelData.isSeparator ? Theme.spaceSm : Theme.rowHeight
            interactive: !modelData.isSeparator
            enabled: modelData.isSeparator || modelData.enabled
            color: !modelData.isSeparator && (mouse.hovered || visualFocus) ? Theme.hover : "transparent"
            border.width: visualFocus ? Theme.borderWidth : 0
            border.color: Theme.focusBorder
            radius: Theme.radius
            accessibleName: modelData.text || "Menu item"
            accessibleDescription: modelData.hasChildren ? "Opens submenu" : "Activates menu action"
            Accessible.role: Accessible.MenuItem
            accessibilityIgnored: modelData.isSeparator
            accessibleCheckable: modelData.buttonType !== QsMenuButtonType.None
            accessibleChecked: modelData.checkState === Qt.Checked
            onTriggered: {
                if (modelData.hasChildren)
                    root.enter(modelData);
                else {
                    modelData.triggered();
                    if (root.dismiss) root.dismiss();
                }
            }
            Keys.onRightPressed: event => {
                // Navigation must never trigger a leaf action.
                if (modelData.hasChildren) root.enter(modelData);
                event.accepted = true;
            }
            Keys.onLeftPressed: event => { root.leave(); event.accepted = true; }
            Keys.onUpPressed: event => { root.moveFocus(menuRow, false); event.accepted = true; }
            Keys.onDownPressed: event => { root.moveFocus(menuRow, true); event.accepted = true; }
            Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.centerIn: parent
                width: parent.width
                height: Theme.borderWidth
                color: Theme.muted
            }
            Line {
                visible: !menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spaceXs
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const e = menuRow.modelData;
                    let prefix = "";
                    if (e.buttonType === QsMenuButtonType.CheckBox)
                        prefix = e.checkState === Qt.Checked ? Icons.check + "  " : Icons.circleOutline + "  ";
                    else if (e.buttonType === QsMenuButtonType.RadioButton)
                        prefix = e.checkState === Qt.Checked ? "●  " : "○  ";
                    return prefix + e.text + (e.hasChildren ? "  ▸" : "");
                }
                color: menuRow.enabled ? Theme.fg : Theme.muted
                elide: Text.ElideRight
            }
            HoverHandler { id: mouse; enabled: menuRow.interactive && menuRow.enabled; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                enabled: menuRow.interactive && menuRow.enabled
                onTapped: {
                    if (settle.running) return;
                    menuRow.forceActiveFocus(Qt.MouseFocusReason);
                    menuRow.activate();
                }
            }
        }
    }
}
