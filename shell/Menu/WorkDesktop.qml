import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

Scope {
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            color: "transparent"
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "nbshell:work-desktop"
            WlrLayershell.layer: WlrLayershell.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            mask: Region { item: desk }

            Connections {
                target: win.contentItem.Window.window
                function onActiveFocusItemChanged() {
                    Qt.callLater(() => {
                        const item = win.contentItem.Window.window.activeFocusItem;
                        if (!item || !item.activeFocusOnTab) return;
                        const pos = item.mapToItem(desk.contentItem, 0, 0);
                        desk.contentY = Math.max(0, Math.min(Math.floor(pos.y - Theme.spaceSm),
                            Math.max(desk.contentY, Math.ceil(pos.y + item.height + Theme.spaceSm - desk.height))));
                    });
                }
            }

            Flickable {
                id: desk
                x: Theme.spaceXl
                y: Theme.barHeight + Theme.spaceXl * 2
                width: Math.max(1, win.width - Theme.spaceXl * 2)
                height: Math.max(1, win.height - y - Theme.spaceXl * 2)
                clip: true
                contentWidth: width
                contentHeight: content.height
                boundsBehavior: Flickable.StopAtBounds
                Keys.onEscapePressed: Config.set("workDesktop", false)
                Column {
                    id: content
                    width: desk.width
                    spacing: Theme.spaceLg
                    Flow {
                        id: header
                        width: parent.width
                        spacing: Theme.spaceXs
                        Repeater {
                            model: ["sessions", "activity", "git", "device", "quotas"]
                            ControlButton {
                                required property string modelData
                                text: "● " + modelData.toUpperCase()
                                implicitWidth: labelWidth.implicitWidth + Theme.spaceLg * 2
                                radius: height / 2
                                selected: WorkState.moduleEnabled(modelData)
                                color: Theme.alpha(Theme.panelSurface, selected ? 0.55 : 0.25)
                                border.width: Theme.borderWidth
                                border.color: visualFocus ? Theme.focusBorder : Theme.alpha(Theme.fg, selected ? 0.35 : 0.15)
                                selectedTextColor: Theme.fg
                                onTriggered: Config.set("workModule_" + modelData, !WorkState.moduleEnabled(modelData))
                                Line { id: labelWidth; visible: false; text: parent.text }
                            }
                        }
                        ControlButton { text: "Hide · Mod+Alt+I"; radius: height / 2; onTriggered: Config.set("workDesktop", false) }
                    }
                    // A single column on narrow displays; separate tall sessions
                    // and compact telemetry rails on larger desktops.
                    Grid {
                        id: grid
                        width: parent.width
                        columns: width >= Theme.cellW * 95 ? 2 : 1
                        columnSpacing: Theme.spaceLg
                        rowSpacing: Theme.spaceLg
                        Column {
                            width: grid.columns === 2 ? (grid.width - grid.columnSpacing) * 0.73 : grid.width
                            spacing: Theme.spaceLg
                            visible: WorkState.moduleEnabled("sessions") || WorkState.moduleEnabled("activity") || WorkState.moduleEnabled("git")
                            Loader { width: parent.width; active: WorkState.moduleEnabled("sessions"); visible: active; source: "WorkSessions.qml" }
                            Loader { width: parent.width; active: WorkState.moduleEnabled("activity"); visible: active; source: "WorkActivity.qml" }
                            Loader { width: parent.width; active: WorkState.moduleEnabled("git"); visible: active; source: "WorkProjects.qml" }
                            Loader { width: parent.width; active: WorkState.moduleEnabled("sessions"); visible: active; source: "WorkRecent.qml" }
                        }

                        Column {
                            width: grid.columns === 2 && (WorkState.moduleEnabled("sessions") || WorkState.moduleEnabled("activity") || WorkState.moduleEnabled("git")) ? (grid.width - grid.columnSpacing) * 0.27 : grid.width
                            spacing: Theme.spaceLg
                            Loader { width: parent.width; active: WorkState.moduleEnabled("quotas"); visible: active; source: "WorkQuotas.qml" }
                            Loader { width: parent.width; active: WorkState.moduleEnabled("device"); visible: active; source: "WorkDevice.qml" }
                        }
                    }
                }
            }
        }
    }
}
