import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets

// Omarchy's split clipboard view, with nbshell's notification history retained.
// Rows carry stable keys, never indices into a concurrently changing service.
Column {
    id: panel
    property var closePopout: null
    property real availableWidth: Theme.activityWidth
    property real availableHeight: Theme.activityHeight
    signal tabRequested(string name)
    readonly property bool clipboard: Runtime.activityTab === "clipboard"
    property string query: ""
    property string selectedKey: ""
    property bool clearArmed: false
    property bool pointerPrimed: false
    property point lastPointer: Qt.point(0,0)
    readonly property Item initialFocusItem: search
    readonly property real frame: 2 * (Theme.activityPadding + Theme.networkBorderWidth)
    width: Math.max(1, Math.min(availableWidth, Theme.activityWidth - frame))
    height: Math.max(1, Math.min(availableHeight, Theme.activityHeight - frame))
    spacing: Theme.activityGap
    readonly property int total: clipboard ? Clipboard.images.length + Clipboard.entries.length : Notify.count
    readonly property var rows: {
        const needle = query.trim().toLowerCase();
        const all = clipboard
            ? Clipboard.images.map(e => ({key:"image:"+e.file, kind:"image", value:e,
                title:"Image", body:"", image:Clipboard.imagePath(e)}))
                .concat(Clipboard.entries.map(e => ({key:"text:"+e, kind:"text", value:e,
                    title:Clipboard.preview(e,200), body:e, image:""})))
            : Notify.history.map(e => ({key:e.key, kind:"notification", value:e,
                title:e.summary || Notify.sourceName(e), body:Notify.plain(e.body || ""), image:""}));
        return all.filter(e => !needle || (e.title+" "+e.body+" "+(e.value.appName || "")).toLowerCase().includes(needle));
    }
    readonly property int selectedIndex: rows.findIndex(e => e.key === selectedKey)
    readonly property var selectedEntry: selectedIndex >= 0 ? rows[selectedIndex] : null

    function reconcile() {
        if (selectedIndex < 0) selectedKey = rows.length ? rows[0].key : "";
        if (selectedIndex >= 0) list.positionViewAtIndex(selectedIndex,ListView.Contain);
    }
    onRowsChanged: { pointerPrimed = false; Qt.callLater(reconcile); }
    onSelectedKeyChanged: {
        preview.contentY = 0;
        Qt.callLater(reconcile);
    }
    onClipboardChanged: {
        query = "";
        cancelClear();
        selectedKey = "";
        Qt.callLater(reconcile);
    }
    function cancelClear() { clearArmed = false; clearReset.stop(); }
    function requestClear() {
        if (!total || (clipboard && Clipboard.removingImage)) return;
        if (!clearArmed) { clearArmed = true; clearReset.restart(); return; }
        cancelClear();
        if (clipboard) Clipboard.clear(); else Notify.clear();
    }
    function activate(key) {
        const row = rows.find(e => e.key === key);
        if (!row) return;
        if (row.kind === "image") Clipboard.copyImage(row.value);
        else if (row.kind === "text") Clipboard.copy(row.value);
        else Notify.focus(row.value);
        closePopout?.();
    }
    function remove(key) {
        const row = rows.find(e => e.key === key);
        if (!row) return;
        // Deletion is separate from activation, including pointer and AT paths.
        if (row.kind === "image") { if (!Clipboard.removingImage) Clipboard.removeImage(row.value); }
        else if (row.kind === "text") Clipboard.remove(row.value);
        else Notify.drop(row.key);
    }
    function previewFromPointer(item, mouse) {
        const point = item.mapToItem(panel,mouse.x,mouse.y);
        const moved = pointerPrimed && (Math.abs(point.x-lastPointer.x)>1 || Math.abs(point.y-lastPointer.y)>1);
        if (!pointerPrimed || moved) lastPointer = point;
        pointerPrimed = true;
        if (moved) selectedKey = item.parent.modelData.key;
    }
    function moveSelection(delta) {
        pointerPrimed = false;
        if (!rows.length) return;
        // Umlaufend wie die Zwischenablage der Referenz (die Panels der
        // Referenz begrenzen dagegen; Audio und Netzwerk tun das jetzt auch).
        const next = ((Math.max(0, selectedIndex) + delta) % rows.length + rows.length) % rows.length;
        selectedKey = rows[next].key;
        list.forceActiveFocus(Qt.TabFocusReason);
    }
    Keys.onEscapePressed: event => {
        if (clearArmed) cancelClear();
        else if (query !== "") query = "";
        else closePopout?.();
        event.accepted = true;
    }
    Timer { id: clearReset; interval: 3000; onTriggered: panel.clearArmed = false }
    component HeaderAction: ActionButton {
        property bool active: false
        compact: true
        height: Theme.controlHeight
        tone: active ? "primary" : "secondary"
        accessibleSelected: active
    }
    Row {
        width: panel.width
        spacing: Theme.networkRowGap
        HeaderAction {
            id: notificationsTab
            text: "Notifications"
            active: !panel.clipboard
            onTriggered: panel.tabRequested("notifications")
        }
        HeaderAction {
            id: clipboardTab
            text: "Clipboard"
            active: panel.clipboard
            onTriggered: panel.tabRequested("clipboard")
        }
        Item { width: Math.max(0,panel.width-notificationsTab.width-clipboardTab.width-dnd.width-clearButton.width-parent.spacing*(panel.clipboard ? 3 : 4)); height: 1 }
        HeaderAction {
            id: dnd
            text: Notify.dnd ? "DND on" : "DND"
            visible: !panel.clipboard
            width: visible ? implicitWidth : 0
            active: Notify.dnd
            onTriggered: Notify.setDnd(!Notify.dnd)
        }
        HeaderAction {
            id: clearButton
            text: panel.clearArmed ? "Confirm clear" : "Clear"
            tone: "danger"
            active: panel.clearArmed
            enabled: panel.total > 0 && !(panel.clipboard && Clipboard.removingImage)
            onTriggered: panel.requestClear()
        }
    }
    TextField {
        id: search
        width: panel.width
        height: Theme.activitySearchHeight
        font.pixelSize: Theme.activityHeadingSize
        accessibleName: panel.clipboard ? "Search clipboard" : "Search notifications"
        placeholderText: accessibleName + "…"
        text: panel.query
        background: null
        horizontalPadding: 0
        onTextEdited: panel.query = text
        Keys.onDownPressed: panel.moveSelection(0)
        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) panel.activate(panel.selectedKey); }
        Keys.onEnterPressed: event => { if (!event.isAutoRepeat) panel.activate(panel.selectedKey); }
    }
    Item {
        width: panel.width
        height: Math.max(1,panel.height - Theme.controlHeight - Theme.activitySearchHeight - footer.height - 3*panel.spacing)
        Row {
            anchors.fill: parent
            spacing: 0
            ListView {
                id: list
                width: parent.width / 2
                height: parent.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: Theme.networkRowGap
                model: panel.rows
                currentIndex: panel.selectedIndex
                activeFocusOnTab: true
                Accessible.role: Accessible.List
                Accessible.name: panel.clipboard ? "Clipboard history" : "Notification history"
                Accessible.description: panel.selectedEntry?.title || "Empty"
                Accessible.focusable: true
                Accessible.focused: activeFocus
                Keys.onUpPressed: panel.moveSelection(-1)
                Keys.onDownPressed: panel.moveSelection(1)
                Keys.onPressed: event => {
                    if (event.modifiers !== Qt.NoModifier || !panel.rows.length) return;
                    if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                        panel.pointerPrimed = false;
                        panel.selectedKey = panel.rows[event.key === Qt.Key_Home ? 0 : panel.rows.length-1].key;
                        event.accepted = true;
                    }
                }
                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) panel.activate(panel.selectedKey); }
                Keys.onEnterPressed: event => { if (!event.isAutoRepeat) panel.activate(panel.selectedKey); }
                Keys.onDeletePressed: event => { if (!event.isAutoRepeat) panel.remove(panel.selectedKey); }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: InteractiveSurface {
                    id: row
                    required property var modelData
                    width: list.width - Theme.activityPadding
                    height: Theme.activityRowHeight
                    readonly property bool selected: panel.selectedKey === modelData.key
                    color: selected ? Theme.menuSelection : pointer.hovered ? Theme.networkHover : "transparent"
                    border.width: selected && list.activeFocus ? Theme.borderWidth : 0
                    border.color: Theme.focusBorder
                    radius: Theme.radius
                    keyboardFocusable: false
                    accessibleRole: Accessible.ListItem
                    accessibleName: modelData.title
                    accessibleDescription: modelData.kind === "notification" ? (modelData.value.urgency === 2 ? "Urgent; " : "") + Notify.sourceName(modelData.value)+"; "+modelData.body : modelData.kind
                    accessibleSelected: selected
                    onTriggered: panel.activate(modelData.key)
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.activityRowPaddingX
                        anchors.rightMargin: Theme.activityRowPaddingX
                        anchors.topMargin: Theme.activityRowPaddingY
                        anchors.bottomMargin: Theme.activityRowPaddingY
                        spacing: Theme.networkRowInset
                        Image {
                            visible: row.modelData.kind === "image"
                            width: visible ? height : 0
                            height: parent.height
                            source: row.modelData.image
                            sourceSize.width: Theme.activityRowHeight * 2
                            sourceSize.height: Theme.activityRowHeight * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Column {
                            width: parent.width - (row.modelData.kind === "image" ? parent.height + parent.spacing : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            Line {
                                width: parent.width
                                text: row.modelData.title
                                font.pixelSize: Theme.networkTitleSize
                                color: row.selected ? Theme.menuSelectedText : Theme.fg
                                elide: Text.ElideRight
                            }
                            Line {
                                visible: row.modelData.kind === "notification"
                                width: parent.width
                                text: visible ? (row.modelData.value.urgency === 2 ? "Urgent · " : "") + Notify.sourceName(row.modelData.value)+" · "+Notify.dayLabel(row.modelData.value.time) : ""
                                color: row.selected ? Theme.menuSelectedText : Theme.networkSecondary
                                font.pixelSize: Theme.networkCaptionSize
                                elide: Text.ElideRight
                            }
                        }
                    }
                    HoverHandler { id: pointer; cursorShape: Qt.PointingHandCursor }
                    // Moving the pointer previews a row; a click retains Omarchy's
                    // immediate copy/open behavior. No nested remove hit target.
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPositionChanged: mouse => panel.previewFromPointer(this,mouse)
                        onClicked: mouse => {
                            panel.selectedKey = row.modelData.key;
                            if (mouse.button === Qt.RightButton) panel.remove(row.modelData.key);
                            else row.activate();
                        }
                    }
                }
            }
            Item {
                width: parent.width / 2
                height: parent.height
                visible: panel.rows.length > 0
                Rectangle {
                    width: Theme.borderWidth; height: parent.height
                    color: Theme.alpha(Theme.fg,0.28)
                }
                Flickable {
                    id: preview
                    activeFocusOnTab: true
                    Accessible.role: Accessible.StaticText
                    Accessible.name: "Selected item preview"
                    Accessible.description: panel.selectedEntry?.body || panel.selectedEntry?.title || ""
                    Accessible.focusable: true
                    Accessible.focused: activeFocus
                    Keys.onUpPressed: contentY = Math.max(0,contentY - Theme.activityRowHeight)
                    Keys.onDownPressed: contentY = Math.min(Math.max(0,contentHeight-height),contentY + Theme.activityRowHeight)
                    Keys.onPressed: event => {
                        if (event.modifiers !== Qt.NoModifier) return;
                        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                            contentY = Math.max(0,Math.min(Math.max(0,contentHeight-height),contentY+(event.key === Qt.Key_PageUp ? -height : height)));
                            event.accepted = true;
                        }
                    }
                    anchors.fill: parent
                    anchors.leftMargin: Theme.activityPadding
                    anchors.bottomMargin: detailActions.height + Theme.networkGap
                    clip: true
                    contentHeight: detail.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Rectangle {
                        parent: preview
                        anchors.fill: parent
                        color: "transparent"
                        border.width: preview.activeFocus ? Theme.borderWidth : 0
                        border.color: Theme.focusBorder
                        z: 1
                    }
                    Column {
                        id: detail
                        width: preview.width - Theme.networkRowGap
                        spacing: Theme.networkGap
                        Line {
                            visible: !panel.clipboard
                            width: parent.width
                            text: visible && panel.selectedEntry ? (panel.selectedEntry.value.urgency === 2 ? "Urgent · " : "") + Notify.sourceName(panel.selectedEntry.value)+" · "+Qt.formatDateTime(panel.selectedEntry.value.time,"ddd d MMM, hh:mm")+((panel.selectedEntry.value.count || 1)>1 ? " · ×"+panel.selectedEntry.value.count : "") : ""
                            font.pixelSize: Theme.networkCaptionSize
                            color: Theme.networkSecondary
                            wrapMode: Text.WrapAnywhere
                        }
                        Line {
                            visible: !panel.clipboard
                            width: parent.width
                            text: panel.selectedEntry?.title || ""
                            font.pixelSize: Theme.networkTitleSize
                            font.bold: true
                            wrapMode: Text.WrapAnywhere
                        }
                        Line {
                            width: parent.width
                            text: panel.selectedEntry?.body || ""
                            font.pixelSize: Theme.networkTitleSize
                            wrapMode: Text.WrapAnywhere
                        }
                        Image {
                            visible: panel.selectedEntry?.kind === "image"
                            width: parent.width
                            height: visible ? preview.height : 0
                            source: panel.selectedEntry?.image || ""
                            sourceSize.width: Math.ceil(preview.width*2)
                            sourceSize.height: Math.ceil(preview.height*2)
                            fillMode: Image.PreserveAspectFit
                            verticalAlignment: Image.AlignTop
                            asynchronous: true
                        }
                    }
                }
                Row {
                    id: detailActions
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.activityPadding
                    anchors.bottom: parent.bottom
                    spacing: Theme.networkRowGap
                    HeaderAction {
                        id: copyButton
                        text: panel.clipboard ? "Copy" : "Open app"
                        enabled: panel.selectedEntry !== null
                        onTriggered: panel.activate(panel.selectedKey)
                    }
                    HeaderAction {
                        id: removeButton
                        text: panel.clipboard ? "Remove" : "Dismiss"
                        busy: panel.selectedEntry?.kind === "image" && Clipboard.removingImage
                        tone: "danger"
                        enabled: panel.selectedEntry !== null
                        onTriggered: panel.remove(panel.selectedKey)
                    }
                }
            }
        }
        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Theme.networkGap
            visible: panel.rows.length === 0
            Line {
                width: parent.width
                text: panel.clipboard ? Icons.clipboard : Icons.bell
                font.pixelSize: Theme.fontDisplay
                horizontalAlignment: Text.AlignHCenter
                color: Theme.networkSecondary
            }
            Line {
                width: parent.width
                text: panel.total ? "No matches" : panel.clipboard ? "Clipboard is empty" : "No notifications yet"
                horizontalAlignment: Text.AlignHCenter
                color: Theme.networkSecondary
            }
        }
    }
    Line {
        id: footer
        width: panel.width
        text: panel.clearArmed ? "Clear all " + (panel.clipboard ? "clipboard items and the current clipboard?" : "notifications? Press Confirm clear.")
            : panel.clipboard ? panel.rows.length + " / " + panel.total + " items · Enter to copy · Delete to remove"
            : panel.rows.length + " / " + panel.total + " notifications · Kept for " + Notify.keepDays + " days"
        color: panel.clearArmed ? Theme.readable(Theme.red,Theme.bg,4.5) : Theme.networkSecondary
        font.pixelSize: Theme.networkCaptionSize
        elide: Text.ElideRight
    }
}
