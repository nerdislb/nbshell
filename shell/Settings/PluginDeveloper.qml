import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Entwickler- und Diagnoseansicht fuer externe Plugins. Sie zeigt nur den
// Zustand der echten Loader; eine vermeintliche Vorschau wuerde fremden Code
// doppelt ausfuehren und bei Services leicht doppelte Nebenwirkungen erzeugen.
PanelWindow {
    id: root

    property int selected: 0
    readonly property var list: Plugins.plugins
    readonly property var plugin: list[selected] ?? null

    visible: Runtime.pluginDeveloperOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:plugin-developer"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() { Runtime.pluginDeveloperOpen = false; }
    function isEnabled(plugin) { return plugin && Plugins.enabledIds.indexOf(plugin.id) >= 0; }
    function toggleEnabled() {
        if (!plugin) return;
        Plugins.setEnabled(plugin.id, !isEnabled(plugin));
    }
    function stateText(plugin, kind) {
        if (kind === "bar-widget") {
            const placed = ["collapsedWidgets", "leftWidgets", "centerWidgets", "rightWidgets"]
                .some(key => Config.value(key, []).indexOf(plugin.id) >= 0);
            return placed ? "scheduled in bar" : "not scheduled";
        }
        if (!isEnabled(plugin)) return "disabled";
        const state = Plugins.loadState(plugin.id, kind);
        return state.state + (state.detail ? "  ·  " + state.detail.replace("file://", "") : "");
    }

    onVisibleChanged: {
        if (visible) {
            selected = Math.max(0, Math.min(selected, list.length - 1));
            keys.forceActiveFocus();
            Plugins.refresh();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min(root.list.length - 1, root.selected + 1)
        Keys.onSpacePressed: root.toggleEnabled()
        Keys.onReturnPressed: root.toggleEnabled()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F5) { Plugins.refresh(); event.accepted = true; }
            if (event.key === Qt.Key_O && root.plugin) {
                Quickshell.execDetached(["xdg-open", root.plugin.dir]);
                event.accepted = true;
            }
        }

        OverlaySurface {
            id: box
            preferredWidth: Theme.cellW * 92
            preferredHeight: Theme.cellH * 33
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.cellW
                spacing: Theme.cellH * 0.25

                PanelHead {
                    rowWidth: box.width - Theme.cellW * 2
                    icon: Icons.cp(0xF12E)
                    title: "Plugin diagnostics"
                    subtitle: "Manifest v2 & runtime"
                    badge: String(root.list.length)
                }
                Rule { rowWidth: box.width - Theme.cellW * 2 }

                Row {
                    width: parent.width
                    height: Theme.cellH * 25
                    spacing: Theme.cellW

                    Column {
                        width: Theme.cellW * 28
                        spacing: 0
                        Line { visible: root.list.length === 0; text: "No external plugins installed"; color: Theme.muted }
                        Repeater {
                            model: root.list
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: Theme.cellW * 28
                                height: Theme.cellH * 2
                                radius: Theme.radius
                                color: index === root.selected ? Theme.selectedSurface(Theme.accent) : "transparent"
                                Line {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.cellW
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (index === root.selected ? "▸ " : "  ") + modelData.name
                                    color: index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg
                                }
                                MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.selected = index; onClicked: root.toggleEnabled() }
                            }
                        }
                    }

                    Rectangle { width: Theme.borderWidth; height: parent.height; color: Theme.muted }

                    Column {
                        width: parent.width - Theme.cellW * 30 - Theme.borderWidth
                        spacing: Theme.cellH * 0.35
                        Line { text: root.plugin ? root.plugin.name + "  " + root.plugin.version : "Select plugin"; color: Theme.fg; font.pixelSize: Theme.fontTitle }
                        Line { visible: !!root.plugin; text: root.plugin ? root.plugin.description : ""; color: Theme.fgDim; wrapMode: Text.WordWrap; width: parent.width }
                        Rule { rowWidth: parent.width }
                        Line { visible: !!root.plugin; text: root.plugin ? "ID             " + root.plugin.id : ""; color: Theme.fgDim }
                        Line { visible: !!root.plugin; text: root.plugin ? "Schema         v" + root.plugin.schemaVersion : ""; color: Theme.fgDim }
                        Line { visible: !!root.plugin; text: root.plugin ? "Author         " + (root.plugin.author || "—") : ""; color: Theme.fgDim }
                        Line { visible: !!root.plugin; text: root.plugin ? "Directory      " + root.plugin.dir : ""; color: Theme.fgDim; elide: Text.ElideMiddle; width: parent.width }
                        Line { visible: !!root.plugin; text: root.plugin ? "Runtime        " + (root.isEnabled(root.plugin) ? "enabled" : "disabled") : ""; color: root.plugin && root.isEnabled(root.plugin) ? Theme.green : Theme.muted }
                        Line { text: "ENTRY POINTS"; color: Theme.fgDim; topPadding: Theme.cellH * 0.5; visible: !!root.plugin }
                        Repeater {
                            model: root.plugin ? root.plugin.kinds : []
                            Line {
                                required property string modelData
                                text: "  " + modelData.padEnd(12) + "  " + root.stateText(root.plugin, modelData)
                                color: root.stateText(root.plugin, modelData).indexOf("error") === 0 ? Theme.red : Theme.fg
                                elide: Text.ElideMiddle
                                width: parent.width
                            }
                        }
                    }
                }
                Rule { rowWidth: box.width - Theme.cellW * 2 }
                Line { text: "↑↓ plugin · Enter/Space runtime on/off · O folder · F5 check · Esc"; color: Theme.muted }
            }
        }
    }
}
