import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "ShoppingListEngine.js" as ShoppingListEngine

PanelWindow {
    id: root

    readonly property string targetGroup: Config.shoppingListTarget
    readonly property var items: ShoppingListEngine.parse(editor.text)
    readonly property string message: ShoppingListEngine.format(items, targetGroup)

    property bool confirmClear: false
    property bool sending: false
    property string statusText: ""
    property bool statusError: false

    visible: Runtime.shoppingListOpen
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:shopping-list"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.shoppingListOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() {
        Runtime.shoppingListOpen = false;
    }

    function sendList() {
        if (root.sending || ShoppingDraft.sending || root.items.length === 0)
            return;
        root.confirmClear = false;
        if (ShoppingDraft.send(root.targetGroup, root.message)) {
            root.sending = true;
            root.statusText = "Sending to “" + root.targetGroup + "”…";
            root.statusError = false;
        }
    }

    function clearList() {
        if (editor.text.trim() === "")
            return;
        if (!root.confirmClear) {
            root.confirmClear = true;
            ShoppingDraft.setStatus("Press “Confirm clear” to discard this draft", true);
            root.statusText = ShoppingDraft.statusText;
            root.statusError = true;
            return;
        }
        root.confirmClear = false;
        ShoppingDraft.clear("Draft cleared");
        editor.text = "";
        root.statusText = "Draft cleared";
        root.statusError = false;
        editor.forceActiveFocus();
    }

    onVisibleChanged: if (visible) {
        editor.text = ShoppingDraft.draft;
        root.confirmClear = false;
        root.sending = ShoppingDraft.sending;
        if (!root.sending)
            ShoppingDraft.setStatus(editor.text.trim() === "" ? "Start with an item, a sentence, or a pasted list" : "Draft restored", false);
        root.statusText = ShoppingDraft.statusText;
        root.statusError = ShoppingDraft.statusError;
        editor.forceActiveFocus();
    }

    Connections {
        target: ShoppingDraft
        function onDraftChanged() {
            if (editor.text !== ShoppingDraft.draft)
                editor.text = ShoppingDraft.draft;
        }
        function onSendStarted() {
            root.sending = true;
            root.statusText = ShoppingDraft.statusText;
            root.statusError = false;
        }
        function onSendFinished(success, message) {
            if (success && editor.text !== "")
                editor.text = "";
            root.sending = false;
            root.statusText = message;
            root.statusError = !success;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: box.opacity * 0.45
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: event => {
            root.close();
            event.accepted = true;
        }

        OverlaySurface {
            id: box
            dockedTop: true
            preferredWidth: Theme.cellW * 104
            preferredHeight: Theme.cellH * 36

            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceXl
                spacing: Theme.spaceMd

                PanelHead {
                    id: header
                    rowWidth: parent.width
                    icon: Icons.cp(0xF0110)
                    title: "Shopping list"
                    subtitle: "WhatsApp group · " + root.targetGroup
                    badge: root.items.length === 1 ? "1 item" : root.items.length + " items"
                    badgeColor: root.items.length > 0 ? Theme.accent : Theme.fgDim
                }

                Rule { id: separator; rowWidth: parent.width }

                Grid {
                    id: workspace
                    width: parent.width
                    height: parent.height - header.height - separator.height - footer.height - parent.spacing * 3
                    columns: width < Theme.cellW * 76 ? 1 : 2
                    spacing: Theme.spaceMd

                    PanelSurface {
                        width: workspace.columns === 1 ? workspace.width : (workspace.width - workspace.spacing) / 2
                        height: workspace.columns === 1 ? (workspace.height - workspace.spacing) / 2 : workspace.height
                        raised: true

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceLg
                            spacing: Theme.spaceSm

                            SectionHeader {
                                width: parent.width
                                text: "Add items"
                                detail: "comma · new line · and"
                            }

                            ScrollView {
                                id: editorScroll
                                width: parent.width
                                height: parent.height - Theme.controlHeight - parent.spacing
                                clip: true
                                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                TextArea {
                                    id: editor
                                    width: editorScroll.availableWidth
                                    placeholderText: "Milk, bread and 6 eggs…"
                                    color: Theme.fg
                                    placeholderTextColor: Theme.muted
                                    selectionColor: Theme.selection
                                    selectedTextColor: Theme.selectedForeground()
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontBody
                                    wrapMode: TextEdit.Wrap
                                    padding: Theme.spaceMd
                                    activeFocusOnTab: true
                                    Accessible.role: Accessible.EditableText
                                    Accessible.name: "Shopping list items"
                                    Accessible.description: "Separate items with a comma, a new line, or the word and"
                                    background: Rectangle {
                                        color: Theme.panelSurface
                                        radius: Theme.radius
                                        border.width: Theme.borderWidth
                                        border.color: editor.activeFocus ? Theme.focusBorder : Theme.panelBorder
                                    }
                                    onTextChanged: {
                                        ShoppingDraft.update(text);
                                        root.confirmClear = false;
                                        if (!root.sending) {
                                            root.statusText = text.trim() === ""
                                                ? "Start with an item, a sentence, or a pasted list"
                                                : "Draft saved locally";
                                            root.statusError = false;
                                        }
                                    }
                                    Keys.onPressed: event => {
                                        if ((event.modifiers & Qt.ControlModifier)
                                                && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                            root.sendList();
                                            event.accepted = true;
                                        }
                                    }
                                    KeyNavigation.tab: sendAction
                                }
                            }
                        }
                    }

                    PanelSurface {
                        width: workspace.columns === 1 ? workspace.width : (workspace.width - workspace.spacing) / 2
                        height: workspace.columns === 1 ? (workspace.height - workspace.spacing) / 2 : workspace.height
                        raised: true

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceLg
                            spacing: Theme.spaceSm

                            SectionHeader {
                                width: parent.width
                                text: "WhatsApp preview"
                                detail: root.targetGroup
                            }

                            ScrollView {
                                width: parent.width
                                height: parent.height - Theme.controlHeight - parent.spacing
                                clip: true
                                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                Column {
                                    width: parent.width
                                    spacing: Theme.spaceSm

                                    Line {
                                        width: parent.width
                                        visible: root.items.length === 0
                                        text: "Your formatted list appears here."
                                        color: Theme.muted
                                        wrapMode: Text.Wrap
                                        Accessible.role: Accessible.StaticText
                                    }

                                    Line {
                                        width: parent.width
                                        visible: root.items.length > 0
                                        text: "🛒  EINKAUF"
                                        color: Theme.accent
                                        font.bold: true
                                        Accessible.role: Accessible.Heading
                                    }

                                    Repeater {
                                        model: root.items
                                        Line {
                                            required property string modelData
                                            width: parent.width
                                            text: "☐  " + modelData
                                            color: Theme.fg
                                            wrapMode: Text.Wrap
                                            Accessible.role: Accessible.ListItem
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    id: footer
                    width: parent.width
                    height: Math.max(statusLine.implicitHeight, sendAction.implicitHeight, clearAction.implicitHeight)
                    spacing: Theme.spaceSm

                    Line {
                        id: statusLine
                        width: Math.max(1, parent.width - sendAction.width - clearAction.width - parent.spacing * 2)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.statusText
                        color: root.statusError ? Theme.yellow : Theme.muted
                        elide: Text.ElideRight
                        Accessible.role: Accessible.StaticText
                        Accessible.name: root.statusText
                    }

                    ActionButton {
                        id: clearAction
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.confirmClear ? "Confirm clear" : "Clear"
                        tone: root.confirmClear ? "danger" : "secondary"
                        enabled: !root.sending && editor.text.trim() !== ""
                        onTriggered: root.clearList()
                        KeyNavigation.tab: sendAction
                        KeyNavigation.backtab: sendAction
                    }

                    ActionButton {
                        id: sendAction
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.sending ? "Sending…" : "Send to WhatsApp"
                        tone: "primary"
                        busy: root.sending
                        enabled: root.items.length > 0
                        onTriggered: root.sendList()
                        KeyNavigation.tab: clearAction
                        KeyNavigation.backtab: editor
                    }
                }
            }
        }
    }
}
