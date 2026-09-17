import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Omarchy 6ea3215 plugins/osd: measured icon + 142px track + fixed readout,
// 16px padding/gaps and 67px edge clearance, scaled through the native theme.
// Keep nbshell's all-screen, opposite-bar placement and pill handoff.
Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
        id: win
        required property var modelData
        readonly property bool takenByPill: Config.osdInPill && Config.mode === "pill"
        readonly property real pad: Math.round(16 * Theme.uiScale)
        readonly property real gap: Math.round(16 * Theme.uiScale)
        readonly property real clearance: Math.round(67 * Theme.uiScale)
        readonly property string symbol: Osd.kind === "brightness" ? Icons.monitor
            : Osd.kind === "mic" ? (Osd.muted ? "󰍭" : "󰍬")
            : Osd.muted || Osd.value <= 0 ? ""
            : Osd.value <= 33 ? Icons.volumeLow : Osd.value <= 66 ? Icons.volumeMid : Icons.volumeHigh
        readonly property real iconWidth: Math.ceil(Math.max(iconMetrics.tightBoundingRect.width, widestIcon.tightBoundingRect.width))
        readonly property real valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, mutedMetrics.advanceWidth))
        screen: modelData
        visible: Osd.showing && !takenByPill
        color: "transparent"
        WlrLayershell.namespace: "nbshell:osd"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors.left: true
        anchors.right: true
        anchors.top: Config.edge === "bottom"
        anchors.bottom: Config.edge !== "bottom"
        implicitHeight: box.height + clearance
        mask: Region {}

        TextMetrics { id: iconMetrics; text: win.symbol; font.family: Theme.fontFamily; font.pixelSize: Theme.fontDisplay }
        TextMetrics { id: widestIcon; text: Icons.volumeHigh; font: iconMetrics.font }
        TextMetrics { id: valueMetrics; text: "100%"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontTitle; font.bold: true }
        TextMetrics { id: mutedMetrics; text: "Muted"; font: valueMetrics.font }
        // MotionSurface statt PanelSurface: die Layer-Animation des Compositors
        // ist aus (Umbriel kennt keinen Schalter je Regel, siehe
        // docs/behaviour-parity.md), also bringt die Flaeche ihre Einblendung
        // aus den geteilten Motion-Tokens selbst mit -- und Reduced Motion
        // wirkt damit auch hier.
        MotionSurface {
            id: box
            visible: win.visible
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: Config.edge === "bottom" ? parent.top : undefined
            anchors.bottom: Config.edge === "bottom" ? undefined : parent.bottom
            anchors.margins: win.clearance
            width: Math.min(win.width - Theme.spaceMd * 2,
                win.iconWidth + Math.round(142 * Theme.uiScale) + win.valueWidth + win.gap * 2 + win.pad * 2 + border.width * 2)
            height: Theme.fontDisplay + win.pad * 2 + border.width * 2
            color: Theme.alpha(Theme.bg, 0.97)
            border.color: Theme.panelBorder
            Accessible.role: Accessible.StaticText
            Accessible.name: Osd.label + ": " + (Osd.muted ? "muted" : Osd.value + "%")
            Row {
                anchors.fill: parent
                anchors.margins: win.pad + box.border.width
                spacing: win.gap
                Item {
                    width: win.iconWidth
                    height: parent.height
                    Line {
                        x: Math.round((win.iconWidth - iconMetrics.tightBoundingRect.width) / 2 - iconMetrics.tightBoundingRect.x)
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.symbol
                        font: iconMetrics.font
                        color: Theme.fg
                    }
                }
                ProgressBar {
                    id: meter
                    width: Math.max(0, parent.width - win.iconWidth - win.valueWidth - win.gap * 2)
                    height: Math.max(Theme.spaceSm, Math.round(6 * Theme.uiScale))
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 100
                    value: Osd.muted ? 0 : Math.max(0, Math.min(100, Osd.value))
                    padding: 0
                    activeFocusOnTab: false
                    Accessible.ignored: true
                    background: Rectangle { color: Theme.alpha(Theme.fg, 0.45) }
                    contentItem: Item {
                        Rectangle {
                            width: parent.width * meter.position
                            height: parent.height
                            color: Theme.accent
                            Behavior on width {
                                enabled: Osd.showing && !Theme.reducedMotion
                                NumberAnimation { duration: Theme.motionSpatialFast; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                }
                Line {
                    width: win.valueWidth
                    anchors.verticalCenter: parent.verticalCenter
                    text: Osd.muted ? "Muted" : Osd.value + "%"
                    font: valueMetrics.font
                    horizontalAlignment: Text.AlignRight
                    color: Theme.fg
                }
            }
        }
    }
}
