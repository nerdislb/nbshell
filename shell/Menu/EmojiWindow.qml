import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: root

    property string query: ""
    property int selected: 0
    readonly property var catalog: [
        {e:"😀",k:"grinsen happy smile"},{e:"😂",k:"lachen traenen lol"},{e:"🙂",k:"laecheln smile"},{e:"😉",k:"zwinkern wink"},{e:"😍",k:"liebe herz eyes"},{e:"🥰",k:"liebe herzen"},{e:"😘",k:"kuss kiss"},{e:"😎",k:"cool sonnenbrille"},{e:"🤔",k:"denken thinking"},{e:"🫡",k:"salut respekt"},{e:"🤯",k:"mind blown wow"},{e:"🥳",k:"party feiern"},{e:"😭",k:"weinen cry"},{e:"😡",k:"wuetend angry"},{e:"😴",k:"schlafen sleep"},{e:"🤖",k:"roboter bot ai ki"},
        {e:"👍",k:"daumen hoch yes ok"},{e:"👎",k:"daumen runter no"},{e:"👏",k:"applaus clap"},{e:"🙏",k:"danke bitte pray"},{e:"🤝",k:"handschlag deal"},{e:"💪",k:"stark muskel"},{e:"👌",k:"ok perfekt"},{e:"✌️",k:"peace sieg"},{e:"🤞",k:"glueck fingers crossed"},{e:"👀",k:"augen sehen"},{e:"🧠",k:"gehirn brain"},{e:"❤️",k:"herz rot liebe"},{e:"💚",k:"herz gruen"},{e:"💙",k:"herz blau"},{e:"💔",k:"herz gebrochen"},{e:"🔥",k:"feuer fire hot"},
        {e:"✅",k:"fertig check done ja"},{e:"❌",k:"falsch nein x"},{e:"⚠️",k:"warnung achtung"},{e:"ℹ️",k:"info information"},{e:"❓",k:"frage question"},{e:"💡",k:"idee licht"},{e:"🎉",k:"party konfetti"},{e:"🚀",k:"rakete launch"},{e:"✨",k:"funkeln sparkle"},{e:"⭐",k:"stern star"},{e:"💯",k:"hundert perfekt"},{e:"📌",k:"pin merken"},{e:"📎",k:"klammer anhang"},{e:"📝",k:"notiz schreiben"},{e:"📅",k:"kalender datum"},{e:"⏰",k:"wecker zeit"},
        {e:"💻",k:"laptop computer"},{e:"⌨️",k:"tastatur keyboard"},{e:"🖥️",k:"monitor desktop"},{e:"📱",k:"telefon handy"},{e:"🔧",k:"werkzeug tool"},{e:"⚙️",k:"einstellung settings"},{e:"🐛",k:"bug fehler"},{e:"🔒",k:"schloss sicherheit"},{e:"🔑",k:"schluessel key"},{e:"📦",k:"paket package"},{e:"🔗",k:"link kette"},{e:"📡",k:"antenne netz"},{e:"☁️",k:"cloud wolke"},{e:"🏠",k:"haus home"},{e:"☕",k:"kaffee coffee"},{e:"🍺",k:"bier beer"},{e:"🌱",k:"pflanze wachsen"},{e:"🎵",k:"musik note"},{e:"🎮",k:"spiel game"},{e:"🇦🇹",k:"oesterreich austria flag"},{e:"🇩🇪",k:"deutschland germany flag"}
    ]
    readonly property var shown: catalog.filter(x => query.trim() === "" || (x.e + " " + x.k).toLowerCase().indexOf(query.toLowerCase().trim()) >= 0)

    visible: Runtime.emojiOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:emoji"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) { query = ""; selected = 0; }
    onQueryChanged: selected = 0

    function choose(index) {
        if (index < 0 || index >= shown.length) return;
        Quickshell.execDetached(["wl-copy", "--", shown[index].e]);
        Runtime.emojiOpen = false;
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const columns = 8;
            if (event.key === Qt.Key_Escape) Runtime.emojiOpen = false;
            else if (event.key === Qt.Key_Backspace) root.query = root.query.slice(0, -1);
            else if (event.key === Qt.Key_Left) root.selected = Math.max(0, root.selected - 1);
            else if (event.key === Qt.Key_Right) root.selected = Math.min(root.shown.length - 1, root.selected + 1);
            else if (event.key === Qt.Key_Up) root.selected = Math.max(0, root.selected - columns);
            else if (event.key === Qt.Key_Down) root.selected = Math.min(root.shown.length - 1, root.selected + columns);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.choose(root.selected);
            else if (event.text && event.text >= " ") root.query += event.text;
            event.accepted = true;
        }
        Rectangle { anchors.fill: parent; color: Theme.scrim }
        MouseArea { anchors.fill: parent; onClicked: Runtime.emojiOpen = false }

        PanelSurface {
            width: Theme.cellW * 55
            height: Theme.cellH * 28
            anchors.centerIn: parent
            accentBorder: true
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.cellH
                Rectangle {
                    width: parent.width
                    height: Theme.controlHeight
                    radius: Theme.radius
                    color: Theme.panelSurfaceRaised
                    border.width: Theme.borderWidth
                    border.color: root.query === "" ? Theme.panelBorder : Theme.focusBorder
                    Line { anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: Theme.spaceLg; anchors.rightMargin: Theme.spaceLg; anchors.verticalCenter: parent.verticalCenter; text: root.query === "" ? "Search emoji …" : root.query; color: root.query === "" ? Theme.muted : Theme.fg; font.pixelSize: Theme.fontSubtitle; elide: Text.ElideRight }
                }
                GridView {
                    width: parent.width
                    height: parent.height - Theme.cellH * 3
                    model: root.shown
                    cellWidth: width / 8
                    cellHeight: Theme.cellH * 3
                    clip: true
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: GridView.view.cellWidth
                        height: GridView.view.cellHeight
                        color: index === root.selected ? Theme.selectedSurface(Theme.accent) : "transparent"
                        radius: Theme.radius
                        border.width: index === root.selected ? Theme.borderWidth : 0
                        border.color: Theme.focusBorder
                        Text { anchors.centerIn: parent; text: modelData.e; font.pixelSize: Theme.fontDisplay }
                        TapHandler { onTapped: root.choose(index) }
                    }
                }
            }
        }
    }
}
