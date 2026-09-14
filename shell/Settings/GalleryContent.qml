import QtQuick
import qs.Common
import qs.Widgets
import qs.Ui as CompatUi

Column {
    id: root
    signal modalRequested(Item trigger)
    clip: true
    width: parent ? parent.width : implicitWidth
    spacing: Theme.spaceLg

    Line { text: "NBSHELL UI GALLERY"; color: Theme.fg; font.pixelSize: Theme.fontHeading; font.bold: true }
    Line { width: parent.width; text: "Shared typography, spacing, accessibility, and interaction states"; color: Theme.fgDim; font.pixelSize: Theme.fontSubtitle; wrapMode: Text.WordWrap }

    SectionHeader { width: parent.width; text: "Bar preview" }
    PanelSurface {
        width: parent.width
        height: barSample.implicitHeight + Theme.spaceSm * 2
        Flow {
            id: barSample
            x: Theme.spaceSm; y: Theme.spaceSm
            width: parent.width - Theme.spaceSm * 2
            spacing: Theme.spaceSm
            ControlButton { text: "1"; selected: true }
            ControlButton { text: "2" }
            Line { text: Icons.agent + "  2 working"; height: Theme.controlHeight; verticalAlignment: Text.AlignVCenter; color: Theme.green }
            Line { text: "12:34"; height: Theme.controlHeight; verticalAlignment: Text.AlignVCenter }
            Line { text: Icons.volumeHigh + "  42%"; height: Theme.controlHeight; verticalAlignment: Text.AlignVCenter; color: Theme.fgDim }
        }
    }

    SectionHeader { width: parent.width; text: "Typography"; detail: root.width >= Theme.cellW * 90 ? (Theme.fontFamily) : "" }
    Flow {
        width: root.width
        spacing: Theme.spaceXl
        Line { text: "CAPTION"; font.pixelSize: Theme.fontCaption; color: Theme.fgDim }
        Line { text: "Body"; font.pixelSize: Theme.fontBody }
        Line { text: "Subtitle"; font.pixelSize: Theme.fontSubtitle }
        Line { text: "Title"; font.pixelSize: Theme.fontTitle; font.bold: true }
        Line { text: "Heading"; font.pixelSize: Theme.fontHeading; font.bold: true }
    }

    SectionHeader { width: parent.width; text: "Controls"; detail: root.width >= Theme.cellW * 90 ? ("normal · selected · focus preview · disabled · urgent") : "" }
    Flow {
        width: root.width
        height: childrenRect.height
        spacing: Theme.spaceSm
        ControlButton { text: "NORMAL" }
        ControlButton { text: "SELECTED"; selected: true }
        ControlButton { text: "FOCUS PREVIEW"; visualFocus: true; interactive: false; accessibilityIgnored: true }
        ControlButton { text: "SELECTED + FOCUS"; selected: true; visualFocus: true; interactive: false; accessibilityIgnored: true }
        ControlButton { text: "DISABLED"; enabled: false }
        ControlButton { text: "URGENT"; danger: true }
        ActionButton {
            id: modalPreviewTrigger
            text: "OPEN MODAL PREVIEW"
            onTriggered: root.modalRequested(modalPreviewTrigger)
        }
    }

    SectionHeader { width: parent.width; text: "Actions"; detail: root.width >= Theme.cellW * 90 ? ("primary · secondary · busy · destructive · long text") : "" }
    Flow {
        width: root.width
        height: childrenRect.height
        spacing: Theme.spaceSm
        ActionButton { text: "APPLY"; tone: "primary" }
        ActionButton { text: "SAVE" }
        ActionButton { text: "SYNC"; busy: true }
        ActionButton { text: "REMOVE"; tone: "danger" }
        ActionButton { width: root.width; text: "A LONG ACTION LABEL THAT MUST REMAIN READABLE" }
    }

    SectionHeader { width: parent.width; text: "Text fields"; detail: root.width >= Theme.cellW * 90 ? ("normal · focus preview · read-only · disabled · password") : "" }
    Flow {
        width: root.width
        height: childrenRect.height
        spacing: Theme.spaceSm
        TextField { width: Theme.cellW * 27; placeholderText: "Search…"; accessibleName: "Gallery search field" }
        TextField { width: Theme.cellW * 27; text: "Visible keyboard focus"; visualFocus: true; readOnly: true; accessibleName: "Focus preview" }
        TextField { width: Theme.cellW * 27; text: "Read-only value"; readOnly: true; accessibleName: "Read-only example" }
        TextField { width: Theme.cellW * 27; text: "Disabled value"; enabled: false; accessibleName: "Disabled example" }
        TextField { width: Theme.cellW * 27; text: "secret"; password: true; accessibleName: "Password example" }
    }

    SectionHeader { width: parent.width; text: "Compatibility inputs"; detail: root.width >= Theme.cellW * 90 ? ("qs.Ui · keyboard · accessibility") : "" }
    Flow {
        width: root.width
        spacing: Theme.spaceLg
        CompatUi.ToggleSwitch { checked: true; accessibleName: "Example setting" }
        CompatUi.NumberField { label: "Seconds"; from: 0; to: 60; value: 10; enabled: false }
    }

    SectionHeader { width: parent.width; text: "Rows"; detail: root.width >= Theme.cellW * 90 ? ("static text · selected · interactive focus") : "" }
    PanelRow { width: parent.width; glyph: Icons.cp(0xF0379); title: "Display"; detail: "1920 × 1080 at 60 Hz"; value: "1×" }
    PanelRow { width: parent.width; glyph: Icons.wifi; title: "Network"; detail: "Connected securely"; value: "ONLINE"; selected: true }
    PanelRow { width: parent.width; glyph: Icons.volumeHigh; title: "Audio focus preview"; detail: "Built-in speakers"; value: "42%"; visualFocus: true; accessibilityIgnored: true }
    PanelRow { width: parent.width; glyph: Icons.circleOutline; title: "A deliberately long status title that demonstrates truncation"; detail: "Long descriptions remain available to assistive technology even when the visible line is elided"; value: "READ ONLY" }

    SectionHeader { width: parent.width; text: "Accessibility contract" }
    Line { width: parent.width; text: "STATIC ROW → StaticText · INTERACTIVE ROW → Button · ENTER / SPACE / AT PRESS → one guarded action"; color: Theme.fgDim; elide: Text.ElideRight }
    Line { width: parent.width; text: "Focus remains visible on selected controls; held activation keys never repeat actions"; color: Theme.fgDim; elide: Text.ElideRight }

    SectionHeader { width: parent.width; text: "Environment" }
    Line { text: "THEME  " + (Theme.isLight ? "LIGHT" : "DARK") + "   MOTION  " + (Theme.reducedMotion ? "REDUCED" : "ENABLED") + "   SCALE  " + Theme.fontSize + " PX"; color: Theme.fg }

    SectionHeader { width: parent.width; text: "Plugin design contract"; detail: root.width >= Theme.cellW * 90 ? ("native API · compatibility API · shared states") : "" }
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
    Flow {
        width: root.width
        spacing: Theme.spaceLg
        PanelSurface { width: Theme.cellW * 25; height: Theme.cellH * 5; accentBorder: false; Line { anchors.centerIn: parent; text: "BASE SURFACE"; color: Theme.fgDim } }
        PanelSurface { width: Theme.cellW * 25; height: Theme.cellH * 5; raised: true; Line { anchors.centerIn: parent; text: "RAISED SURFACE"; color: Theme.accent } }
    }

    Item { width: 1; height: Theme.spaceLg }
}
