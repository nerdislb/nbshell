import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Cell {
    id: root

    readonly property var buds: Plugins.serviceFor("io.github.nerdislb.buds-control")
    readonly property var device: buds ? buds.device : null
    readonly property int shownMode: buds && buds.actionPending ? buds.pendingMode : (buds ? buds.currentMode : 0)
    readonly property string fullMode: buds ? buds.modeLabel(shownMode) : "Disconnected"
    readonly property string compactMode: {
        if (!buds || !buds.backendAvailable) return "SETUP";
        if (!buds.connected) return "OFFLINE";
        if (fullMode === "Noise Cancellation") return "ANC";
        if (fullMode === "Transparency") return "AWARE";
        if (fullMode === "Adaptive") return "ADAPT";
        if (fullMode === "Off") return "OFF";
        return fullMode.toUpperCase();
    }
    readonly property color modeColor: {
        if (!buds || !buds.connected) return Theme.fgDim;
        if (fullMode === "Transparency") return Theme.cyan;
        if (fullMode === "Noise Cancellation" || fullMode === "Adaptive") return Theme.accent;
        return Theme.fgDim;
    }

    function batteryText(level, status) {
        if (status === "not-reported" || status === "disconnected")
            return "—";
        return Math.round(Number(level || 0)) + "%";
    }

    function batteryDetail(status) {
        if (status === "charging") return "Charging";
        if (status === "discharging") return "In use";
        if (status === "full") return "Full";
        return "Not reported";
    }

    shown: true
    quiet: !buds || !buds.connected
    interactive: true
    popoutTakesKeyboard: true
    slotChars: buds && buds.connected ? 14 : 9
    label: "BUDS"
    icon: String.fromCodePoint(0xF02CB)
    text: buds && buds.connected ? (compactMode + " · " + buds.batteryLevel + "%") : compactMode
    color: modeColor

    onClicked: if (buds) buds.refresh()
    onRightClicked: if (buds && buds.backend === "budslink") buds.openBudsLink()

    preview: Component {
        BarPreview {
            icon: root.icon
            title: root.device ? String(root.device.alias) : "Buds Control"
            subtitle: root.buds && root.buds.backendAvailable
                ? (root.buds.connected ? "Enhanced Bluetooth controls" : "No supported earbuds connected")
                : "A headset backend is required"
            badge: root.compactMode
            badgeColor: root.modeColor
            content: [
                Facts {
                    rowWidth: parent.width
                    pairs: root.device ? [
                        { "label": "Left", "value": root.batteryText(root.device.state.battery1Level, root.device.state.battery1Status) },
                        { "label": "Right", "value": root.batteryText(root.device.state.battery2Level, root.device.state.battery2Status) },
                        { "label": "Case", "value": root.batteryText(root.device.state.battery3Level, root.device.state.battery3Status) },
                        { "label": "Mode", "value": root.fullMode, "color": root.modeColor }
                    ] : []
                }
            ]
        }
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null
            readonly property real rowWidth: Theme.cellW * 50
            readonly property var leftBattery: root.buds ? root.buds.battery("Left bud", "battery1Level", "battery1Status") : ({})
            readonly property var rightBattery: root.buds ? root.buds.battery("Right bud", "battery2Level", "battery2Status") : ({})
            readonly property var caseBattery: root.buds ? root.buds.battery("Case", "battery3Level", "battery3Status") : ({})
            readonly property var batteries: [leftBattery, rightBattery, caseBattery]

            width: rowWidth
            spacing: Theme.spaceMd
            focus: true

            Component.onCompleted: forceActiveFocus()
            Keys.onEscapePressed: if (closePopout) closePopout()

            PanelHead {
                rowWidth: panel.rowWidth
                icon: root.icon
                title: root.device ? String(root.device.alias) : "Buds Control"
                subtitle: root.buds && root.buds.backendAvailable
                    ? (root.buds.connected ? "Enhanced headset control" : "Waiting for supported earbuds")
                    : "Headset backend unavailable"
                badge: root.compactMode
                badgeColor: root.modeColor
            }

            Column {
                width: panel.rowWidth
                spacing: Theme.spaceSm
                visible: root.buds && root.buds.connected

                Rule {
                    rowWidth: panel.rowWidth
                    label: "BATTERY"
                }

                Row {
                    width: panel.rowWidth
                    spacing: Theme.spaceLg

                    Repeater {
                        model: panel.batteries

                        Column {
                            id: batteryColumn
                            required property var modelData
                            width: (panel.rowWidth - Theme.spaceLg * 2) / 3
                            spacing: Theme.spaceXs

                            Line {
                                width: parent.width
                                text: batteryColumn.modelData.label || "Battery"
                                color: Theme.fg
                                font.pixelSize: Theme.fontBody
                                elide: Text.ElideRight
                            }

                            LevelBar {
                                width: parent.width
                                cells: 11
                                value: Number(batteryColumn.modelData.level || 0)
                                interactive: false
                                enabled: batteryColumn.modelData.available === true
                                fillColor: Number(batteryColumn.modelData.level || 0) <= 20 ? Theme.red : Theme.accent
                            }

                            Line {
                                width: parent.width
                                text: root.batteryText(batteryColumn.modelData.level, batteryColumn.modelData.status)
                                    + "  ·  " + root.batteryDetail(batteryColumn.modelData.status)
                                color: batteryColumn.modelData.available === true ? Theme.fgDim : Theme.muted
                                font.pixelSize: Theme.fontCaption
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Rule {
                    rowWidth: panel.rowWidth
                    label: "NOISE CONTROL"
                }

                Segments {
                    rowWidth: panel.rowWidth
                    options: root.device ? root.device.modes : []
                    current: root.shownMode
                    enabled: root.buds && root.buds.controlsAvailable && !root.buds.actionPending
                    onChosen: value => root.buds.setMode(value)
                }

                Line {
                    width: panel.rowWidth
                    visible: root.buds && root.buds.statusText !== ""
                    text: root.buds ? root.buds.statusText : ""
                    color: root.buds && root.buds.actionPending ? Theme.yellow : Theme.green
                    font.pixelSize: Theme.fontCaption
                    wrapMode: Text.WordWrap
                }
            }

            PanelRow {
                width: panel.rowWidth
                visible: root.buds && root.buds.backendAvailable && !root.buds.connected
                title: "No supported earbuds connected"
                detail: "Connect the headset in Bluetooth, then refresh."
                glyph: Icons.bluetooth
            }

            PanelRow {
                width: panel.rowWidth
                visible: !root.buds || !root.buds.backendAvailable
                title: "Headset controls are not available"
                detail: "Install pbpctrl for Pixel Buds or BudsLink for another supported headset."
                glyph: Icons.bluetoothOff
            }

            Line {
                width: panel.rowWidth
                visible: root.buds && root.buds.errorText !== ""
                text: root.buds ? root.buds.errorText : ""
                color: Theme.red
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.WordWrap
            }

            Rule {
                rowWidth: panel.rowWidth
                label: root.buds && root.buds.version !== "" ? "BUDSLINK " + root.buds.version + "  ·  LIVE DBUS" : "OPTIONAL BACKEND"
            }

            Row {
                width: panel.rowWidth
                spacing: Theme.spaceSm

                ControlButton {
                    text: root.buds && root.buds.loading ? "Refreshing…" : "Refresh"
                    enabled: root.buds && !root.buds.loading
                    onTriggered: root.buds.refresh()
                }

                ControlButton {
                    visible: root.buds && root.buds.backend === "budslink"
                    text: "Open full settings"
                    onTriggered: root.buds.openBudsLink()
                }

                ControlButton {
                    visible: !root.buds || !root.buds.backendAvailable
                    text: "Get BudsLink"
                    onTriggered: if (root.buds) root.buds.openInstallPage()
                }
            }
        }
    }
}