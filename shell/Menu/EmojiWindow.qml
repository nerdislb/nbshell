import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Common/MenuLayout.js" as MenuLayout

// Omarchy emoji-card geometry over the existing native clipboard picker.
PanelWindow {
    id: root

    readonly property string query: search.text
    property string selectedKey: "😀"
    property bool committed: false
    property bool gridFocusWanted: false
    property var pointerPosition: null
    readonly property var catalog: [
        {"e": "😀", "k": "grinsen happy smile", "name": "Grinning face"},
        {"e": "😂", "k": "lachen traenen lol", "name": "Tears of joy"},
        {"e": "🙂", "k": "laecheln smile", "name": "Slight smile"},
        {"e": "😉", "k": "zwinkern wink", "name": "Wink"},
        {"e": "😍", "k": "liebe herz eyes", "name": "Heart eyes"},
        {"e": "🥰", "k": "liebe herzen", "name": "Smiling face with hearts"},
        {"e": "😘", "k": "kuss kiss", "name": "Blowing a kiss"},
        {"e": "😎", "k": "cool sonnenbrille", "name": "Sunglasses"},
        {"e": "🤔", "k": "denken thinking", "name": "Thinking face"},
        {"e": "🫡", "k": "salut respekt", "name": "Saluting face"},
        {"e": "🤯", "k": "mind blown wow", "name": "Exploding head"},
        {"e": "🥳", "k": "party feiern", "name": "Party face"},
        {"e": "😭", "k": "weinen cry", "name": "Crying face"},
        {"e": "😡", "k": "wuetend angry", "name": "Angry face"},
        {"e": "😴", "k": "schlafen sleep", "name": "Sleeping face"},
        {"e": "🤖", "k": "roboter bot ai ki", "name": "Robot"},
        {"e": "👍", "k": "daumen hoch yes ok", "name": "Thumbs up"},
        {"e": "👎", "k": "daumen runter no", "name": "Thumbs down"},
        {"e": "👏", "k": "applaus clap", "name": "Clapping hands"},
        {"e": "🙏", "k": "danke bitte pray", "name": "Folded hands"},
        {"e": "🤝", "k": "handschlag deal", "name": "Handshake"},
        {"e": "💪", "k": "stark muskel", "name": "Flexed biceps"},
        {"e": "👌", "k": "ok perfekt", "name": "OK hand"},
        {"e": "✌️", "k": "peace sieg", "name": "Victory hand"},
        {"e": "🤞", "k": "glueck fingers crossed", "name": "Crossed fingers"},
        {"e": "👀", "k": "augen sehen", "name": "Eyes"},
        {"e": "🧠", "k": "gehirn brain", "name": "Brain"},
        {"e": "❤️", "k": "herz rot liebe", "name": "Red heart"},
        {"e": "💚", "k": "herz gruen", "name": "Green heart"},
        {"e": "💙", "k": "herz blau", "name": "Blue heart"},
        {"e": "💔", "k": "herz gebrochen", "name": "Broken heart"},
        {"e": "🔥", "k": "feuer fire hot", "name": "Fire"},
        {"e": "✅", "k": "fertig check done ja", "name": "Check mark"},
        {"e": "❌", "k": "falsch nein x", "name": "Cross mark"},
        {"e": "⚠️", "k": "warnung achtung", "name": "Warning"},
        {"e": "ℹ️", "k": "info information", "name": "Information"},
        {"e": "❓", "k": "frage question", "name": "Question mark"},
        {"e": "💡", "k": "idee licht", "name": "Light bulb"},
        {"e": "🎉", "k": "party konfetti", "name": "Party popper"},
        {"e": "🚀", "k": "rakete launch", "name": "Rocket"},
        {"e": "✨", "k": "funkeln sparkle", "name": "Sparkles"},
        {"e": "⭐", "k": "stern star", "name": "Star"},
        {"e": "💯", "k": "hundert perfekt", "name": "Hundred points"},
        {"e": "📌", "k": "pin merken", "name": "Pushpin"},
        {"e": "📎", "k": "klammer anhang", "name": "Paperclip"},
        {"e": "📝", "k": "notiz schreiben", "name": "Memo"},
        {"e": "📅", "k": "kalender datum", "name": "Calendar"},
        {"e": "⏰", "k": "wecker zeit", "name": "Alarm clock"},
        {"e": "💻", "k": "laptop computer", "name": "Laptop"},
        {"e": "⌨️", "k": "tastatur keyboard", "name": "Keyboard"},
        {"e": "🖥️", "k": "monitor desktop", "name": "Desktop computer"},
        {"e": "📱", "k": "telefon handy", "name": "Mobile phone"},
        {"e": "🔧", "k": "werkzeug tool", "name": "Wrench"},
        {"e": "⚙️", "k": "einstellung settings", "name": "Gear"},
        {"e": "🐛", "k": "bug fehler", "name": "Bug"},
        {"e": "🔒", "k": "schloss sicherheit", "name": "Locked"},
        {"e": "🔑", "k": "schluessel key", "name": "Key"},
        {"e": "📦", "k": "paket package", "name": "Package"},
        {"e": "🔗", "k": "link kette", "name": "Link"},
        {"e": "📡", "k": "antenne netz", "name": "Satellite antenna"},
        {"e": "☁️", "k": "cloud wolke", "name": "Cloud"},
        {"e": "🏠", "k": "haus home", "name": "House"},
        {"e": "☕", "k": "kaffee coffee", "name": "Coffee"},
        {"e": "🍺", "k": "bier beer", "name": "Beer"},
        {"e": "🌱", "k": "pflanze wachsen", "name": "Seedling"},
        {"e": "🎵", "k": "musik note", "name": "Musical note"},
        {"e": "🎮", "k": "spiel game", "name": "Game controller"},
        {"e": "🇦🇹", "k": "oesterreich austria flag", "name": "Flag Austria"},
        {"e": "🇩🇪", "k": "deutschland germany flag", "name": "Flag Germany"}
    ]
    readonly property var shown: catalog.filter(item => !query.trim()
        || (item.e + " " + item.k + " " + item.name).toLowerCase().includes(query.toLowerCase().trim()))
    readonly property int selected: shown.findIndex(item => item.e === selectedKey)
    // Scoped metrics from Omarchy Emojis.qml at the pinned Quattro revision.
    readonly property real preferredWidth: Math.round(400 * Theme.menuScale)
    readonly property real preferredHeight: Math.round(500 * Theme.menuScale)
    readonly property real cellSize: Math.max(Math.round(44 * Theme.menuScale), Theme.fontDisplay + Theme.spaceMd)
    readonly property int columns: Math.max(1, Math.floor(grid.width / cellSize))

    visible: Runtime.emojiOpen
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:emoji"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.emojiOpen = false; }
    function copyEmoji(emoji) { Quickshell.execDetached(["wl-copy", "--", emoji]); }
    function choose(emoji) {
        if (committed || !Runtime.emojiOpen || !shown.some(item => item.e === emoji)) return;
        committed = true;
        copyEmoji(emoji);
        close();
    }
    function revealSelection() {
        if (selected >= 0) grid.positionViewAtIndex(selected, GridView.Contain);
    }
    function focusSelection() {
        if (selected < 0) { search.forceActiveFocus(); return; }
        gridFocusWanted = true;
        revealSelection();
        Qt.callLater(() => {
            if (root.visible && root.gridFocusWanted && grid.currentItem)
                grid.currentItem.forceActiveFocus(Qt.TabFocusReason);
        });
    }
    function move(delta, wrap) {
        pointerPosition = null;
        if (!shown.length) return;
        const index = wrap ? MenuLayout.nextIndex(Math.max(0, selected), delta, shown.length)
            : Math.max(0, Math.min(shown.length - 1, Math.max(0, selected) + delta));
        selectedKey = shown[index].e;
        focusSelection();
    }
    function edge(last) {
        pointerPosition = null;
        if (!shown.length) return;
        selectedKey = shown[last ? shown.length - 1 : 0].e;
        focusSelection();
    }
    function focusSearch(selectAll) {
        gridFocusWanted = false;
        search.forceActiveFocus(Qt.ShortcutFocusReason);
        if (selectAll) search.selectAll();
    }
    function handleEscape() {
        if (query.length) { search.clear(); focusSearch(false); }
        else close();
    }
    function pointTo(item, mouse) {
        const point = item.mapToItem(root.contentItem, mouse.x, mouse.y);
        if (MenuLayout.moved(pointerPosition, point)) {
            selectedKey = item.modelData.e;
            // Keep the native editor focused while searching/using an IME.
            if (!search.activeFocus) {
                gridFocusWanted = true;
                item.forceActiveFocus(Qt.MouseFocusReason);
            }
        }
        if (pointerPosition === null || MenuLayout.moved(pointerPosition, point)) pointerPosition = point;
    }
    onShownChanged: {
        selectedKey = shown.length ? shown[0].e : "";
        pointerPosition = null;
        gridFocusWanted = false;
        grid.contentY = 0;
        Qt.callLater(() => root.focusSearch(false));
    }
    onSelectedChanged: Qt.callLater(revealSelection)
    onColumnsChanged: Qt.callLater(revealSelection)
    Component.onCompleted: Qt.callLater(() => root.focusSearch(false))

    Rectangle { anchors.fill: parent; color: Theme.menuScrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }
    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: event => { if (!event.isAutoRepeat) root.handleEscape(); event.accepted = true; }
        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_F || event.key === Qt.Key_L)) {
                root.focusSearch(true); event.accepted = true; return;
            }
            if (search.activeFocus || (event.modifiers !== Qt.NoModifier && event.modifiers !== Qt.ShiftModifier)) return;
            if (event.key === Qt.Key_Left) root.move(-1, true);
            else if (event.key === Qt.Key_Right) root.move(1, true);
            else if (event.key === Qt.Key_Up) root.move(-root.columns, false);
            else if (event.key === Qt.Key_Down) root.move(root.columns, false);
            else if (event.key === Qt.Key_Home) root.edge(false);
            else if (event.key === Qt.Key_End) root.edge(true);
            else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)
                root.move((event.key === Qt.Key_PageUp ? -1 : 1) * root.columns * Math.max(1, Math.floor(grid.height / grid.cellHeight)), false);
            else if (event.text && event.text >= " " && event.key !== Qt.Key_Delete) {
                root.focusSearch(false);
                search.insert(search.cursorPosition, event.text);
            } else return;
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
            MouseArea { anchors.fill: parent }
            TextField {
                id: search
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.menuInset
                height: Theme.menuHeaderHeight
                accessibleName: "Search emojis"
                accessibleDescription: "Search by name or keyword; Down or Tab moves to results; Enter copies the selection"
                placeholderText: "Search emojis…"
                font.pixelSize: Theme.fontHeading
                horizontalPadding: 0
                background: Rectangle {
                    color: "transparent"
                    radius: Theme.radius
                    border.width: search.activeFocus ? Theme.borderWidth : 0
                    border.color: Theme.focusBorder
                }
                onActiveFocusChanged: if (activeFocus) root.gridFocusWanted = false
                KeyNavigation.tab: grid.currentItem || search
                KeyNavigation.backtab: grid.currentItem || search
                Keys.onDownPressed: root.focusSelection()
                Keys.onUpPressed: root.focusSelection()
                Keys.onReturnPressed: event => { if (!event.isAutoRepeat && !inputMethodComposing) root.choose(root.selectedKey); event.accepted = true; }
                Keys.onEnterPressed: event => { if (!event.isAutoRepeat && !inputMethodComposing) root.choose(root.selectedKey); event.accepted = true; }
                Keys.onEscapePressed: event => { if (!event.isAutoRepeat) root.handleEscape(); event.accepted = true; }
            }
            GridView {
                id: grid
                anchors.top: search.bottom
                anchors.topMargin: Theme.spaceMd
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.leftMargin: Theme.menuInset
                anchors.rightMargin: Theme.menuInset
                anchors.bottomMargin: Theme.spaceMd
                model: root.shown
                currentIndex: root.selected
                cellWidth: Math.min(root.cellSize, width)
                cellHeight: root.cellSize
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                onHeightChanged: Qt.callLater(root.revealSelection)
                onCurrentItemChanged: if (root.gridFocusWanted) Qt.callLater(root.focusSelection)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: InteractiveSurface {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool selected: modelData.e === root.selectedKey
                    width: grid.cellWidth
                    height: grid.cellHeight
                    color: selected ? Theme.menuSelection : "transparent"
                    radius: Theme.radius
                    border.width: activeFocus ? Theme.borderWidth : 0
                    border.color: Theme.focusBorder
                    keyboardFocusable: selected
                    accessibleName: modelData.name + " " + modelData.e
                    accessibleDescription: "Copy emoji to clipboard"
                    accessibleRole: Accessible.Button
                    accessibleSelected: selected
                    KeyNavigation.tab: search
                    KeyNavigation.backtab: search
                    onActiveFocusChanged: if (activeFocus) { root.gridFocusWanted = true; root.selectedKey = modelData.e; Qt.callLater(root.revealSelection); }
                    onTriggered: root.choose(modelData.e)
                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: cell.modelData.e
                        font.pixelSize: Theme.fontDisplay
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.pointTo(cell, {x: mouseX, y: mouseY})
                        onPositionChanged: mouse => root.pointTo(cell, mouse)
                        onClicked: { cell.forceActiveFocus(Qt.MouseFocusReason); cell.activate(); }
                    }
                }
            }
            Line {
                anchors.fill: grid
                visible: root.shown.length === 0
                text: "No matching emojis"
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
                text: "Enter copies · Esc clears / closes"
                color: Theme.networkSecondary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }
        }
    }
}
