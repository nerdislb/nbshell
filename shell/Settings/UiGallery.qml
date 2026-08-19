import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: root

    visible: Runtime.uiGalleryOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:ui-gallery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.uiGalleryOpen = false; }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()

        OverlaySurface {
            preferredWidth: Theme.cellW * 72
            preferredHeight: Theme.overlayHeightMedium
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                spacing: Theme.spaceLg

                Line { text: "NBSHELL UI GALLERY"; color: Theme.fg; font.pixelSize: Theme.fontHeading; font.bold: true }
                Line { text: "Shared typography, spacing, surfaces, and interaction states"; color: Theme.fgDim; font.pixelSize: Theme.fontSubtitle }

                SectionHeader { width: parent.width; text: "Typography"; detail: Theme.fontFamily }
                Row {
                    spacing: Theme.spaceXl
                    Line { text: "CAPTION"; font.pixelSize: Theme.fontCaption; color: Theme.fgDim }
                    Line { text: "Body"; font.pixelSize: Theme.fontBody }
                    Line { text: "Subtitle"; font.pixelSize: Theme.fontSubtitle }
                    Line { text: "Title"; font.pixelSize: Theme.fontTitle; font.bold: true }
                    Line { text: "Heading"; font.pixelSize: Theme.fontHeading; font.bold: true }
                }

                SectionHeader { width: parent.width; text: "Controls"; detail: "normal · hover · selected · disabled · urgent" }
                Row {
                    spacing: Theme.spaceSm
                    ControlButton { text: "NORMAL" }
                    ControlButton { text: "SELECTED"; selected: true }
                    ControlButton { text: "DISABLED"; enabled: false }
                    ControlButton { text: "URGENT"; danger: true }
                }

                SectionHeader { width: parent.width; text: "Rows" }
                PanelRow { width: parent.width; glyph: Icons.cp(0xF0379); title: "Display"; detail: "1920 × 1080 at 60 Hz"; value: "1×" }
                PanelRow { width: parent.width; glyph: Icons.wifi; title: "Network"; detail: "Connected securely"; value: "ONLINE"; selected: true }
                PanelRow { width: parent.width; glyph: Icons.volumeHigh; title: "Audio"; detail: "Built-in speakers"; value: "42%"; interactive: true }

                SectionHeader { width: parent.width; text: "Surface hierarchy" }
                Row {
                    spacing: Theme.spaceLg
                    PanelSurface { width: Theme.cellW * 25; height: Theme.cellH * 5; accentBorder: false; Line { anchors.centerIn: parent; text: "BASE SURFACE"; color: Theme.fgDim } }
                    PanelSurface { width: Theme.cellW * 25; height: Theme.cellH * 5; raised: true; Line { anchors.centerIn: parent; text: "RAISED SURFACE"; color: Theme.accent } }
                }
            }
        }
    }
}
