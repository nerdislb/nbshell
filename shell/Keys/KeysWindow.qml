import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Searchable compositor shortcuts, presented as the same top-docked shell panel
// used by Dashboard, Agents, Modules, and Settings.
PanelWindow {
    id: root

    property string query: ""
    property int offset: 0

    readonly property real rowHeight: Theme.controlHeight
    readonly property int rowsPerColumn: Math.max(4,
        Math.floor((box.height - Theme.cellH * 8.2) / root.rowHeight))
    readonly property int rowsPerPage: root.rowsPerColumn * 2
    readonly property var rows: {
        const needle = root.query.toLowerCase().trim();
        const matches = Binds.list.filter(binding => needle === ""
            || (binding.taste + " " + binding.text + " " + binding.aktion + " " + binding.gruppe)
                .toLowerCase().indexOf(needle) >= 0);
        const result = [];
        for (let groupIndex = 0; groupIndex < Binds.gruppen.length; groupIndex++) {
            const group = Binds.gruppen[groupIndex];
            const entries = matches.filter(binding => binding.gruppe === group);
            if (!entries.length)
                continue;
            result.push({ "header": true, "text": group, "count": entries.length });
            for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
                result.push({
                    "header": false,
                    "key": entries[entryIndex].taste,
                    "text": entries[entryIndex].text
                });
            }
        }
        return result;
    }
    readonly property int maximumOffset: Math.max(0, root.rows.length - root.rowsPerPage)

    visible: Runtime.keysOpen
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:keys"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.keysOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.keysOpen = false; }
    function move(amount) {
        root.offset = Math.max(0, Math.min(root.offset + amount, root.maximumOffset));
    }

    onVisibleChanged: if (visible) {
        query = "";
        offset = 0;
        Binds.ensure();
        keys.forceActiveFocus();
    }
    onQueryChanged: offset = 0

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity * 0.45 }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Escape:
                if (root.query !== "") root.query = "";
                else root.close();
                break;
            case Qt.Key_Backspace:
                root.query = root.query.slice(0, -1);
                break;
            case Qt.Key_Down:
                root.move(1);
                break;
            case Qt.Key_Up:
                root.move(-1);
                break;
            case Qt.Key_PageDown:
            case Qt.Key_Right:
                root.move(root.rowsPerPage);
                break;
            case Qt.Key_PageUp:
            case Qt.Key_Left:
                root.move(-root.rowsPerPage);
                break;
            case Qt.Key_Home:
                root.offset = 0;
                break;
            case Qt.Key_End:
                root.offset = root.maximumOffset;
                break;
            case Qt.Key_F5:
                Binds.load();
                break;
            default:
                if (event.text && event.text.length === 1 && event.text >= " ")
                    root.query += event.text;
                break;
            }
            event.accepted = true;
        }

        OverlaySurface {
            id: box
            dockedTop: true
            preferredWidth: Theme.cellW * 112
            preferredHeight: Theme.cellH * 34

            MouseArea { anchors.fill: parent; onClicked: {} }
            WheelHandler {
                onWheel: wheelEvent => root.move(wheelEvent.angleDelta.y > 0 ? -3 : 3)
            }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW * 2
                spacing: Theme.spaceSm

                PanelHead {
                    rowWidth: parent.width
                    icon: Icons.keyboard
                    title: root.query !== "" ? root.query : "Keyboard shortcuts"
                    subtitle: "Umbriel · type to search"
                    badge: Binds.loading ? "…" : String(Binds.list.length)
                }

                Rule { rowWidth: parent.width }

                Line {
                    visible: Binds.problem !== ""
                    width: parent.width
                    text: Binds.problem
                    color: Theme.yellow
                    elide: Text.ElideRight
                }

                Line {
                    visible: Binds.problem === "" && root.rows.length === 0
                    width: parent.width
                    text: Binds.loading ? "Reading configuration…" : "No shortcuts found"
                    color: Theme.muted
                    horizontalAlignment: Text.AlignHCenter
                }

                Row {
                    width: parent.width
                    height: root.rowsPerColumn * root.rowHeight
                    spacing: Theme.spaceLg

                    component ShortcutColumn: PanelSurface {
                        id: shortcutColumn
                        property int start: 0

                        width: (parent.width - parent.spacing) / 2
                        height: parent.height
                        raised: true

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceSm
                            spacing: 0

                            Repeater {
                                model: root.rows.slice(shortcutColumn.start,
                                    shortcutColumn.start + root.rowsPerColumn)

                                Item {
                                    id: shortcutRow
                                    required property var modelData
                                    width: parent.width
                                    height: root.rowHeight

                                    SectionHeader {
                                        visible: shortcutRow.modelData.header
                                        width: parent.width
                                        height: parent.height
                                        text: shortcutRow.modelData.text
                                        detail: String(shortcutRow.modelData.count)
                                    }

                                    Rectangle {
                                        id: keycap
                                        visible: !shortcutRow.modelData.header
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.cellW * 18
                                        height: Theme.cellH * 1.45
                                        radius: Theme.radius
                                        color: Theme.panelSurface
                                        border.width: Theme.borderWidth
                                        border.color: Theme.panelBorder

                                        Line {
                                            anchors.centerIn: parent
                                            width: parent.width - Theme.spaceSm * 2
                                            text: shortcutRow.modelData.key || ""
                                            color: Theme.fg
                                            font.pixelSize: Theme.fontCaption
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Line {
                                        visible: !shortcutRow.modelData.header
                                        anchors.left: keycap.right
                                        anchors.leftMargin: Theme.spaceLg
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: shortcutRow.modelData.text || ""
                                        color: Theme.fgDim
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    ShortcutColumn { start: root.offset }
                    ShortcutColumn { start: root.offset + root.rowsPerColumn }
                }

                Rule { rowWidth: parent.width }

                Item {
                    width: parent.width
                    height: Theme.cellH * 1.4

                    Line {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.cellW * 18
                        text: "↑↓ browse · ←→ page · F5 refresh · Esc close"
                        color: Theme.muted
                        font.pixelSize: Theme.fontCaption
                        elide: Text.ElideRight
                    }

                    Line {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.rows.length > root.rowsPerPage
                            ? (root.offset + 1) + "–" + Math.min(root.offset + root.rowsPerPage, root.rows.length)
                                + " / " + root.rows.length
                            : ""
                        color: Theme.muted
                        font.pixelSize: Theme.fontCaption
                    }
                }
            }
        }
    }
}
