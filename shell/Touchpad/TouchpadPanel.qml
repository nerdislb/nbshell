import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import "Curve.js" as Curve

FocusScope {
    id: root
    property bool autoLoad: true
    property var state: ({})
    property var saved: ({})
    property var draft: ({profile: "system", curve: Curve.presetForScale(1)})
    property string message: "Loading touchpad settings…"
    property bool failed: false
    property bool loaded: false
    property bool confirmClose: false
    property bool allowClose: false
    property real gainMaximum: 1
    property int hits: 0
    readonly property bool busy: backend.running
    readonly property bool dirty: loaded && JSON.stringify(draft) !== JSON.stringify(saved)
    readonly property bool custom: draft.profile === "mac" || draft.profile === "custom"
    readonly property string backendPath: decodeURIComponent(String(Qt.resolvedUrl("../scripts/touchpad.py")).replace(/^file:\/\//, ""))
    signal closeRequested()
    focus: true
    Keys.onEscapePressed: closeRequested()

    function set(key, value) {
        const next = Curve.copy(draft);
        next[key] = value;
        draft = next;
    }
    function choose(profile) {
        const next = Curve.copy(draft);
        next.profile = profile;
        if (profile === "mac") next.curve = Curve.presetForScale(gainMaximum);
        draft = next;
    }
    function adjust(handle, value) {
        const next = Curve.copy(draft);
        next.profile = "custom";
        next.curve = Curve.adjust(next.curve, handle, value, true, gainMaximum);
        draft = next;
    }
    function request(action) {
        if (busy) return;
        failed = false;
        message = action === "status" ? "Reading configuration…" : "Validating and applying…";
        backend.command = ["python3", backendPath, action];
        backend.payload = JSON.stringify({revision: state.revision, settings: draft});
        backend.running = true;
    }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            const item = root.Window.window?.activeFocusItem;
            if (!item) return;
            let ancestor = item;
            while (ancestor && ancestor !== form) ancestor = ancestor.parent;
            if (ancestor !== form) return;
            const point = item.mapToItem(form, 0, 0);
            const flick = scroll.contentItem;
            if (point.y < flick.contentY) flick.contentY = point.y;
            else if (point.y + item.height > flick.contentY + scroll.availableHeight)
                flick.contentY = Math.max(0, point.y + item.height - scroll.availableHeight);
        }
    }
    Component.onCompleted: if (autoLoad) request("status")
    Process {
        id: backend
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload); stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.error) throw new Error(result.error);
                    root.state = result;
                    root.saved = Curve.copy(result.settings);
                    root.draft = Curve.copy(result.settings);
                    root.gainMaximum = Math.max(1, result.settings.curve?.fast ?? 1);
                    root.loaded = true;
                    root.message = "Configuration loaded. Draft edits only change the pointer after Apply.";
                } catch (error) { root.failed = true; root.message = String(error); }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) { root.failed = true; root.message = text.trim(); } }
        onExited: (code, status) => { stdinEnabled = true; if (code && !root.failed) { root.failed = true; root.message = "Touchpad helper failed (" + code + "). Refresh to retry."; } }
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.panelPadding
        spacing: Theme.spaceMd
        Row {
            width: parent.width
            spacing: Theme.spaceMd
            Line { width: parent.width - close.implicitWidth - parent.spacing; text: "TOUCHPAD"; font.pixelSize: Theme.fontHeading; font.bold: true }
            ControlButton { id: close; text: "ESC  CLOSE"; onTriggered: root.closeRequested() }
        }
        Line {
            id: notice
            width: parent.width
            text: root.message
            color: root.failed ? Theme.readable(Theme.red, Theme.panelSurface, 4.5) : Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5)
            wrapMode: Text.WordWrap
        }
        Flow {
            id: confirmation
            visible: root.confirmClose
            width: parent.width
            spacing: Theme.spaceSm
            Line { text: "Discard unapplied changes?" }
            ControlButton { text: "KEEP EDITING"; onTriggered: root.confirmClose = false }
            ControlButton { text: "DISCARD & CLOSE"; onTriggered: { root.allowClose = true; root.closeRequested(); } }
        }
        Controls.ScrollView {
            id: scroll
            objectName: "touchpadScroll"
            width: parent.width
            height: Math.max(0, parent.height - headerSpace())
            function headerSpace() { return Theme.controlHeight + notice.height + footer.height + (confirmation.visible ? confirmation.height + Theme.spaceMd : 0) + Theme.spaceMd * 3; }
            contentWidth: availableWidth
            clip: true
            Column {
                id: form
                width: scroll.availableWidth
                spacing: Theme.spaceLg
                enabled: root.loaded && !root.busy
                Line {
                    width: parent.width
                    text: (root.state.devices ?? []).map(d => d.name).join("\n") || "No connected touchpad detected."
                    wrapMode: Text.WrapAnywhere
                    color: Theme.accent
                }
                Line { width: parent.width; text: root.state.scope ?? ""; wrapMode: Text.WordWrap; color: Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5) }
                Repeater {
                    model: root.state.warnings ?? []
                    Line { required property string modelData; width: parent.width; text: modelData; wrapMode: Text.WordWrap; color: Theme.readable(Theme.yellow, Theme.panelSurface, 4.5) }
                }
                SectionHeader { width: parent.width; text: "Pointer feel" }
                Segments {
                    rowWidth: parent.width
                    options: [{label: "SYSTEM", value: "system"}, {label: "ADAPTIVE", value: "adaptive"}, {label: "FLAT", value: "flat"}, {label: "MAC-INSPIRED", value: "mac"}, {label: "CUSTOM", value: "custom"}]
                    current: root.draft.profile
                    onChosen: value => root.choose(value)
                }
                Line { width: parent.width; text: root.draft.profile === "external" ? "Existing custom profile is preserved. Choose Custom to replace it with an editable curve." : "Mac-inspired approximates pointer acceleration, not macOS scrolling, gestures or haptics."; wrapMode: Text.WordWrap; color: Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5) }
                NumberSetting {
                    visible: !root.custom
                    width: parent.width
                    label: "Pointer speed"; minimum: -1; maximum: 1; step: .01
                    value: root.draft.sensitivity ?? 0
                    detail: root.draft.sensitivity === undefined ? "system default until edited" : ""
                    onEdited: value => root.set("sensitivity", value)
                }
                Column {
                    visible: root.custom
                    width: parent.width
                    spacing: Theme.spaceMd
                    NumberSetting { width: parent.width; label: "Curve editor range (does not rescale the curve)"; minimum: .1; maximum: 10; step: .1; value: root.gainMaximum; suffix: "×"; onEdited: value => root.gainMaximum = Math.max(value, root.draft.curve.fast) }
                    CurveGraph { width: parent.width; curve: root.draft.curve; maximum: root.gainMaximum; onAdjusted: (handle, value) => root.adjust(handle, value) }
                    Line { width: parent.width; text: "Drag P/S/E/F or use arrow keys. Shift gives larger steps."; color: Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5); wrapMode: Text.WordWrap }
                    NumberSetting { width: parent.width; label: "Precision"; minimum: .01; maximum: root.gainMaximum; step: .001; decimals: 4; value: root.draft.curve.precision; suffix: "×"; onEdited: value => root.adjust(0, value) }
                    NumberSetting { width: parent.width; label: "Acceleration start"; maximum: (root.draft.curve.end - .2) * 25; step: 1; value: root.draft.curve.start * 25; suffix: "%"; onEdited: value => root.adjust(1, value / 25) }
                    NumberSetting { width: parent.width; label: "Acceleration end"; minimum: (root.draft.curve.start + .2) * 25; maximum: 100; step: 1; value: root.draft.curve.end * 25; suffix: "%"; onEdited: value => root.adjust(2, value / 25) }
                    NumberSetting { width: parent.width; label: "Fast swipes"; minimum: root.draft.curve.precision; maximum: root.gainMaximum; step: .001; decimals: 4; value: root.draft.curve.fast; suffix: "×"; onEdited: value => root.adjust(3, value) }
                }
                SectionHeader { width: parent.width; text: "Scrolling & clicking" }
                NumberSetting { width: parent.width; label: "Scroll speed · all touchpads"; minimum: .1; maximum: 10; step: .01; value: root.draft.scroll_factor ?? 1; suffix: "×"; detail: root.draft.scroll_factor === undefined ? "system default until edited" : ""; onEdited: value => root.set("scroll_factor", value) }
                Repeater {
                    model: [{key: "natural_scroll", label: "Natural scrolling"}, {key: "tap", label: "Tap to click"}, {key: "disable_while_typing", label: "Disable while typing"}]
                    Column {
                        required property var modelData
                        width: parent.width
                        spacing: Theme.spaceXs
                        Line { width: parent.width; text: modelData.label; wrapMode: Text.WordWrap }
                        Segments {
                            rowWidth: parent.width
                            options: [{label: "INHERIT", value: "inherit"}, {label: "ON", value: true}, {label: "OFF", value: false}]
                            current: root.draft[modelData.key] ?? "inherit"
                            onChosen: value => {
                                if (value === "inherit") { const next = Curve.copy(root.draft); delete next[modelData.key]; root.draft = next; }
                                else root.set(modelData.key, value);
                            }
                        }
                    }
                }
                Line { text: "Physical click method" }
                Segments {
                    rowWidth: parent.width
                    options: [{label: "INHERIT", value: "inherit"}, {label: "CLICKFINGER", value: "clickfinger"}, {label: "BUTTON AREAS", value: "button_areas"}]
                    current: root.draft.click_method ?? "inherit"
                    onChosen: value => {
                        if (value === "inherit") { const next = Curve.copy(root.draft); delete next.click_method; root.draft = next; }
                        else root.set("click_method", value);
                    }
                }
                SectionHeader { width: parent.width; text: "Try after Apply" }
                Line { width: parent.width; text: "Click the numbered target to check small corrections and longer movements. Hits: " + root.hits; wrapMode: Text.WordWrap; color: Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5) }
                Item {
                    width: parent.width
                    height: Theme.cellH * 7
                    ControlButton {
                        text: String(root.hits + 1)
                        x: Math.max(0, parent.width - width) * [0.1, .85, .4, .65, .2][root.hits % 5]
                        y: Math.max(0, parent.height - height) * [.1, .7, .4, .05, .8][root.hits % 5]
                        onTriggered: root.hits++
                    }
                }
                Line { width: parent.width; text: "Curve math adapted from Trackpad Plus by Andrew Kent and David Fano · MIT"; wrapMode: Text.WordWrap; color: Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5); font.pixelSize: Theme.fontCaption }
            }
        }
        Flow {
            id: footer
            width: parent.width
            spacing: Theme.spaceSm
            ControlButton { text: root.busy ? "WORKING…" : "APPLY & TRY"; selected: root.dirty; enabled: root.loaded && !root.busy && root.dirty; onTriggered: root.request("apply") }
            ControlButton { text: "RESTORE PREVIOUS"; enabled: root.state.canRestore === true && !root.busy && !root.dirty; onTriggered: root.request("restore") }
            ControlButton { text: root.dirty ? "DISCARD DRAFT" : "REFRESH"; enabled: !root.busy; onTriggered: root.request("status") }
        }
    }
}
