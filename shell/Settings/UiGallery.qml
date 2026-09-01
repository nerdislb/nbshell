import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Ui as CompatUi

PanelWindow {
    id: root

    visible: true
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:ui-gallery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.uiGalleryOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Runtime.uiGalleryOpen = false; }
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FocusScope {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.close()
        Keys.priority: Keys.AfterItem
        Keys.onPressed: event => {
            const maximum = Math.max(0, viewport.contentHeight - viewport.height);
            const step = Theme.rowHeight * 2;
            if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                viewport.contentY = Math.min(maximum, viewport.contentY + step);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                viewport.contentY = Math.max(0, viewport.contentY - step);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                viewport.contentY = Math.min(maximum, viewport.contentY + viewport.height * 0.8);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageUp) {
                viewport.contentY = Math.max(0, viewport.contentY - viewport.height * 0.8);
                event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                viewport.contentY = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                viewport.contentY = maximum;
                event.accepted = true;
            }
        }

        OverlaySurface {
            id: box
            preferredWidth: Theme.cellW * 72
            preferredHeight: Theme.overlayHeightMedium
            MouseArea { anchors.fill: parent; onClicked: {} }

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: Theme.panelPadding
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: content
                    width: viewport.width
                    spacing: Theme.spaceLg

                    Line { text: "NBSHELL UI GALLERY"; color: Theme.fg; font.pixelSize: Theme.fontHeading; font.bold: true }
                    Line { width: parent.width; text: "Shared typography, spacing, accessibility, and interaction states"; color: Theme.fgDim; font.pixelSize: Theme.fontSubtitle; wrapMode: Text.WordWrap }

                    SectionHeader { width: parent.width; text: "Typography"; detail: Theme.fontFamily }
                    Row {
                        spacing: Theme.spaceXl
                        Line { text: "CAPTION"; font.pixelSize: Theme.fontCaption; color: Theme.fgDim }
                        Line { text: "Body"; font.pixelSize: Theme.fontBody }
                        Line { text: "Subtitle"; font.pixelSize: Theme.fontSubtitle }
                        Line { text: "Title"; font.pixelSize: Theme.fontTitle; font.bold: true }
                        Line { text: "Heading"; font.pixelSize: Theme.fontHeading; font.bold: true }
                    }

                    SectionHeader { width: parent.width; text: "Controls"; detail: "normal · selected · focus preview · disabled · urgent" }
                    Flow {
                        width: viewport.width
                        height: childrenRect.height
                        spacing: Theme.spaceSm
                        ControlButton { text: "NORMAL" }
                        ControlButton { text: "SELECTED"; selected: true }
                        ControlButton { text: "FOCUS PREVIEW"; visualFocus: true; interactive: false; accessibilityIgnored: true }
                        ControlButton { text: "SELECTED + FOCUS"; selected: true; visualFocus: true; interactive: false; accessibilityIgnored: true }
                        ControlButton { text: "DISABLED"; enabled: false }
                        ControlButton { text: "URGENT"; danger: true }
                    }

                    SectionHeader { width: parent.width; text: "Actions"; detail: "primary · secondary · busy · destructive · long text" }
                    Flow {
                        width: viewport.width
                        height: childrenRect.height
                        spacing: Theme.spaceSm
                        ActionButton { text: "APPLY"; tone: "primary" }
                        ActionButton { text: "SAVE" }
                        ActionButton { text: "SYNC"; busy: true }
                        ActionButton { text: "REMOVE"; tone: "danger" }
                        ActionButton { width: viewport.width; text: "A LONG ACTION LABEL THAT MUST REMAIN READABLE" }
                    }

                    SectionHeader { width: parent.width; text: "Compatibility inputs"; detail: "qs.Ui · keyboard · accessibility" }
                    Row {
                        spacing: Theme.spaceLg
                        CompatUi.ToggleSwitch { checked: true; accessibleName: "Example setting" }
                        CompatUi.NumberField { label: "Seconds"; from: 0; to: 60; value: 10; enabled: false }
                    }

                    SectionHeader { width: parent.width; text: "Rows"; detail: "static text · selected · interactive focus" }
                    PanelRow { width: parent.width; glyph: Icons.cp(0xF0379); title: "Display"; detail: "1920 × 1080 at 60 Hz"; value: "1×" }
                    PanelRow { width: parent.width; glyph: Icons.wifi; title: "Network"; detail: "Connected securely"; value: "ONLINE"; selected: true }
                    PanelRow { width: parent.width; glyph: Icons.volumeHigh; title: "Audio focus preview"; detail: "Built-in speakers"; value: "42%"; visualFocus: true; accessibilityIgnored: true }
                    PanelRow { width: parent.width; glyph: Icons.circleOutline; title: "A deliberately long status title that demonstrates truncation"; detail: "Long descriptions remain available to assistive technology even when the visible line is elided"; value: "READ ONLY" }

                    SectionHeader { width: parent.width; text: "Accessibility contract" }
                    Line { width: parent.width; text: "STATIC ROW → StaticText · INTERACTIVE ROW → Button · ENTER / SPACE / AT PRESS → one guarded action"; color: Theme.fgDim; elide: Text.ElideRight }
                    Line { width: parent.width; text: "Focus remains visible on selected controls; held activation keys never repeat actions"; color: Theme.fgDim; elide: Text.ElideRight }

                    SectionHeader { width: parent.width; text: "Environment" }
                    Line { text: "THEME  " + (Theme.isLight ? "LIGHT" : "DARK") + "   MOTION  " + (Theme.reducedMotion ? "REDUCED" : "ENABLED") + "   SCALE  " + Theme.fontSize + " PX"; color: Theme.fg }

                    SectionHeader { width: parent.width; text: "Plugin design contract"; detail: "native API · compatibility API · shared states" }
                    PanelSurface {
                        width: parent.width
                        height: contractContent.implicitHeight + Theme.spaceLg * 2
                        raised: true

                        Column {
                            id: contractContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spaceLg
                            anchors.rightMargin: Theme.spaceLg
                            spacing: Theme.spaceSm

                            Line { width: parent.width; text: "NATIVE  qs.Common + qs.Widgets"; color: Theme.fg }
                            Line { width: parent.width; text: "COMPAT  qs.Commons + qs.Ui"; color: Theme.fgDim }
                            Line { width: parent.width; text: "STATES  normal · hover-cursor · focus · selected · pressed · urgent"; color: Theme.fgDim }
                            Line { width: parent.width; text: "MOTION  effects " + Theme.motionEffectsDefault + " ms · spatial " + Theme.motionSpatialDefault + " ms · exit " + Theme.motionExit + " ms"; color: Theme.fgDim }
                            Line { width: parent.width; text: "SCAFFOLD  nbshell plugin new <id> --kind <kind>"; color: Theme.accent }
                        }
                    }

                    SectionHeader { width: parent.width; text: "Surface hierarchy" }
                    Row {
                        spacing: Theme.spaceLg
                        PanelSurface { width: Theme.cellW * 25; height: Theme.cellH * 5; accentBorder: false; Line { anchors.centerIn: parent; text: "BASE SURFACE"; color: Theme.fgDim } }
                        PanelSurface { width: Theme.cellW * 25; height: Theme.cellH * 5; raised: true; Line { anchors.centerIn: parent; text: "RAISED SURFACE"; color: Theme.accent } }
                    }

                    Item { width: 1; height: Theme.spaceLg }
                }
            }
        }
    }
}
