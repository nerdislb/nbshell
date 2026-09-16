import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Common/MenuLayout.js" as MenuLayout
import "../Widgets/FocusScroll.js" as FocusScroll

// Omarchy's wide keybinding search, with native groups and read-only semantics.
PanelWindow {
    id: root

    readonly property string query: search.text
    property string selectedKey: ""
    property bool listFocusWanted: false
    property var pointerPosition: null
    readonly property var matches: Binds.list.filter(binding => !query.trim() || (binding.taste + " " + binding.text + " " + binding.aktion + " " + binding.gruppe).toLowerCase().includes(query.toLowerCase().trim()))
    readonly property var rows: {
        const groups = Binds.gruppen.concat(matches.map(binding => binding.gruppe || "Other").filter((group, index, values) => !Binds.gruppen.includes(group) && values.indexOf(group) === index));
        const result = [];
        for (const group of groups) {
            const entries = matches.filter(binding => (binding.gruppe || "Other") === group);
            if (!entries.length)
                continue;
            result.push({
                header: true,
                text: group,
                count: entries.length,
                uid: "group:" + group
            });
            for (const binding of entries) {
                result.push({
                    header: false,
                    key: binding.taste,
                    text: binding.text,
                    uid: JSON.stringify([group, binding.taste, binding.aktion, binding.text])
                });
            }
        }
        return result;
    }
    readonly property int selected: rows.findIndex(row => !row.header && row.uid === selectedKey)
    readonly property bool compact: list.width < Theme.cellW * 60
    // omarchy-menu-keybindings requests an 800px-wide, 500px-high select menu.
    readonly property real preferredWidth: Math.round(800 * Theme.menuScale)
    readonly property real preferredHeight: Math.round(500 * Theme.menuScale)

    visible: Runtime.keysOpen
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:keys"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() {
        Runtime.keysOpen = false;
    }
    function handleEscape() {
        if (query.length) {
            search.clear();
            focusSearch(false);
        } else
            close();
    }
    function focusSearch(selectAll) {
        listFocusWanted = false;
        search.forceActiveFocus(Qt.ShortcutFocusReason);
        if (selectAll)
            search.selectAll();
    }
    function revealSelection() {
        const item = rowsRepeater.itemAt(root.selected);
        list.currentItem = item;
        if (item)
            list.contentY = FocusScroll.contentYForFocus(item.y, item.height, list.contentY, list.height, list.contentHeight, 0);
    }
    function focusSelection() {
        if (selected < 0) {
            focusSearch(false);
            return;
        }
        listFocusWanted = true;
        revealSelection();
        Qt.callLater(() => {
            if (root.visible && root.listFocusWanted && list.currentItem)
                list.currentItem.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    function move(delta) {
        pointerPosition = null;
        const entries = rows.filter(row => !row.header);
        if (!entries.length)
            return;
        const index = Math.max(0, entries.findIndex(row => row.uid === selectedKey));
        selectedKey = entries[Math.max(0, Math.min(entries.length - 1, index + delta))].uid;
        focusSelection();
    }
    function edge(last) {
        pointerPosition = null;
        const entries = rows.filter(row => !row.header);
        if (!entries.length)
            return;
        selectedKey = entries[last ? entries.length - 1 : 0].uid;
        focusSelection();
    }
    function refresh() {
        if (Binds.loading) return;
        // Move focus before disabling the button; Qt clears activeFocus first.
        if (refreshButton.activeFocus) focusSearch(false);
        Binds.load();
    }
    function pointTo(item, mouse) {
        if (item.modelData.header)
            return;
        const point = item.mapToItem(root.contentItem, mouse.x, mouse.y);
        if (MenuLayout.moved(pointerPosition, point)) {
            selectedKey = item.modelData.uid;
            if (listFocusWanted)
                item.forceActiveFocus(Qt.MouseFocusReason);
        }
        if (pointerPosition === null || MenuLayout.moved(pointerPosition, point))
            pointerPosition = point;
    }
    onRowsChanged: {
        if (!rows.some(row => !row.header && row.uid === selectedKey))
            selectedKey = rows.find(row => !row.header)?.uid || "";
        pointerPosition = null;
        Qt.callLater(() => {
            if (root.listFocusWanted)
                root.focusSelection();
            else
                root.revealSelection();
        });
    }
    onSelectedChanged: Qt.callLater(revealSelection)
    Component.onCompleted: {
        Binds.ensure();
        Qt.callLater(() => root.focusSearch(false));
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.menuScrim
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }
    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: event => {
            if (!event.isAutoRepeat)
                root.handleEscape();
            event.accepted = true;
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) {
                if (!event.isAutoRepeat)
                    root.refresh();
                event.accepted = true;
                return;
            }
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_F || event.key === Qt.Key_L)) {
                root.focusSearch(true);
                event.accepted = true;
                return;
            }
            if (!root.listFocusWanted || (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ShiftModifier))
                return;
            if (event.key === Qt.Key_Up)
                root.move(-1);
            else if (event.key === Qt.Key_Down)
                root.move(1);
            else if (event.key === Qt.Key_Home)
                root.edge(false);
            else if (event.key === Qt.Key_End)
                root.edge(true);
            else if ([Qt.Key_PageUp, Qt.Key_Left, Qt.Key_PageDown, Qt.Key_Right].includes(event.key))
                root.move(([Qt.Key_PageUp, Qt.Key_Left].includes(event.key) ? -1 : 1) * Math.max(1, Math.floor(list.height / Theme.menuBaseRowHeight)));
            else if (event.text && event.text >= " " && event.key !== Qt.Key_Delete) {
                root.focusSearch(false);
                search.insert(search.cursorPosition, event.text);
            } else
                return;
            event.accepted = true;
        }
        MotionSurface {
            id: box
            motionEnabled: false
            anchors.centerIn: parent
            width: Math.max(1, Math.min(root.preferredWidth, parent.width - Theme.menuScreenMargin * 2))
            height: Math.max(1, Math.min(root.preferredHeight, parent.height - Theme.menuScreenMargin * 2))
            color: Theme.bg
            border.width: Theme.menuBorderWidth
            border.color: Theme.fg
            clip: true
            MouseArea {
                anchors.fill: parent
            }
            TextField {
                id: search
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: refreshButton.left
                anchors.topMargin: Theme.menuInset
                anchors.leftMargin: Theme.menuInset
                anchors.rightMargin: Theme.spaceMd
                height: Theme.menuHeaderHeight
                accessibleName: "Search keyboard shortcuts"
                placeholderText: "Search keybindings…"
                font.pixelSize: Theme.fontHeading
                horizontalPadding: 0
                background: Rectangle {
                    color: "transparent"
                    radius: Theme.radius
                    border.width: search.activeFocus ? Theme.borderWidth : 0
                    border.color: Theme.focusBorder
                }
                onActiveFocusChanged: if (activeFocus)
                    root.listFocusWanted = false
                KeyNavigation.tab: refreshButton.enabled ? refreshButton : list.currentItem || search
                KeyNavigation.backtab: list.currentItem || (refreshButton.enabled ? refreshButton : search)
                Keys.onDownPressed: root.focusSelection()
                Keys.onUpPressed: root.focusSelection()
                // Read-only help: Enter moves focus, never dispatches a binding.
                Keys.onReturnPressed: event => {
                    if (!event.isAutoRepeat && !inputMethodComposing)
                        root.focusSelection();
                    event.accepted = true;
                }
                Keys.onEnterPressed: event => {
                    if (!event.isAutoRepeat && !inputMethodComposing)
                        root.focusSelection();
                    event.accepted = true;
                }
            }
            ControlButton {
                id: refreshButton
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.menuInset
                height: Theme.menuHeaderHeight
                text: "Refresh"
                accessibleName: "Refresh keyboard shortcuts"
                enabled: !Binds.loading
                onTriggered: root.refresh()
                onActiveFocusChanged: if (activeFocus)
                    root.listFocusWanted = false
                onEnabledChanged: if (!enabled && activeFocus)
                    root.focusSearch(false)
                KeyNavigation.tab: list.currentItem || search
                KeyNavigation.backtab: search
            }
            Line {
                id: status
                anchors.top: search.bottom
                anchors.topMargin: Theme.menuGap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.menuInset
                anchors.rightMargin: Theme.menuInset
                text: Binds.loading ? "Reading shortcuts…" : Binds.problem ? "Unable to refresh shortcuts: " + Binds.problem : ""
                visible: text.length > 0
                font.pixelSize: Theme.fontCaption
                color: Binds.problem && !Binds.loading ? Theme.readable(Theme.yellow, Theme.bg, 4.5) : Theme.networkSecondary
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Accessible.name: text
            }
            Flickable {
                id: list
                property var currentItem: null
                anchors.top: status.visible ? status.bottom : search.bottom
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
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
                Column {
                    id: column
                    width: list.width
                    spacing: Theme.menuRowSpacing
                    Repeater {
                        id: rowsRepeater
                        model: root.rows
                        InteractiveSurface {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool selected: !modelData.header && modelData.uid === root.selectedKey
                            width: list.width
                            height: modelData.header ? Math.max(Theme.menuHeaderHeight, groupLabel.implicitHeight + Theme.spaceSm * 2) : Math.max(Theme.menuBaseRowHeight, (root.compact ? keyLabel.implicitHeight + description.implicitHeight + Theme.spaceXs : Math.max(keyLabel.implicitHeight, description.implicitHeight)) + Theme.spaceSm * 2)
                            color: selected ? Theme.menuSelection : "transparent"
                            radius: Theme.radius
                            border.width: activeFocus ? Theme.borderWidth : 0
                            border.color: Theme.focusBorder
                            interactive: !modelData.header
                            keyboardFocusable: selected
                            accessibleName: modelData.header ? modelData.text + ", " + modelData.count + " shortcuts" : modelData.key + ": " + modelData.text
                            accessibleDescription: modelData.header ? "" : "Keyboard shortcut reference"
                            accessibleRole: modelData.header ? Accessible.StaticText : Accessible.ListItem
                            accessibleSelected: selected
                            KeyNavigation.tab: search
                            KeyNavigation.backtab: refreshButton.enabled ? refreshButton : search
                            onActiveFocusChanged: if (activeFocus) {
                                root.listFocusWanted = true;
                                root.selectedKey = modelData.uid;
                                Qt.callLater(root.revealSelection);
                            }
                            onTriggered: {
                                root.selectedKey = modelData.uid;
                                root.focusSelection();
                            }
                            Line {
                                id: groupLabel
                                visible: row.modelData.header
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Theme.menuRowInset
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.header ? row.modelData.text + " · " + row.modelData.count : ""
                                font.pixelSize: Theme.fontCaption
                                color: Theme.networkSecondary
                                wrapMode: Text.WordWrap
                            }
                            Line {
                                id: keyLabel
                                visible: !row.modelData.header
                                x: Theme.menuRowInset
                                y: root.compact ? Theme.spaceSm : (row.height - height) / 2
                                width: root.compact ? row.width - Theme.menuRowInset * 2 : Math.min(Theme.cellW * 28, (row.width - Theme.menuRowInset * 2) * 0.38)
                                text: row.modelData.key || ""
                                font.pixelSize: Theme.menuFontSize
                                color: row.selected ? Theme.menuSelectedText : Theme.fg
                                wrapMode: Text.WrapAnywhere
                            }
                            Line {
                                id: description
                                visible: !row.modelData.header
                                x: root.compact ? Theme.menuRowInset : keyLabel.x + keyLabel.width + Theme.menuGap
                                y: root.compact ? keyLabel.y + keyLabel.height + Theme.spaceXs : (row.height - height) / 2
                                width: row.width - x - Theme.menuRowInset
                                text: row.modelData.header ? "" : row.modelData.text || ""
                                font.pixelSize: Theme.menuFontSize
                                color: row.selected ? Theme.menuSelectedText : Theme.fg
                                wrapMode: Text.Wrap
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !row.modelData.header
                                hoverEnabled: true
                                onEntered: root.pointTo(row, {
                                    x: mouseX,
                                    y: mouseY
                                })
                                onPositionChanged: mouse => root.pointTo(row, mouse)
                                onClicked: row.activate()
                            }
                        }
                    }
                }
            }
            Line {
                anchors.fill: list
                visible: root.matches.length === 0 && !Binds.loading
                text: Binds.problem ? "Shortcuts unavailable" : root.query ? "No matching shortcuts" : "No shortcuts configured"
                color: Theme.networkSecondary
                font.pixelSize: Theme.fontTitle
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
            }
            Line {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.menuInset
                text: root.matches.length + " / " + Binds.list.length + " shortcuts · Reference only · F5 refresh · Esc clears / closes"
                color: Theme.networkSecondary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }
    }
}
