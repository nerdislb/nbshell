import QtQuick
import QtQuick.Controls as Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Ui as Ui

// Omarchy's audio hierarchy on the native nbshell popup/Audio service.
// Routing and Bluetooth codec controls are retained below the core sections.
Column {
    id: panel
    property var closePopout: null
    property var audio: Audio
    property real availableWidth: Theme.audioWidth
    readonly property real rowWidth: Math.max(1, Math.min(
        Theme.audioWidth - 2 * (Theme.audioPadding + Theme.audioBorderWidth), availableWidth))
    readonly property Item initialFocusItem: audio.ready ? outputVolume : powerSwitch
    readonly property bool hasInput: !!audio.source?.audio
    readonly property bool anyAudible: (audio.ready && !audio.muted) || (hasInput && !audio.micMuted)
    width: rowWidth
    spacing: Theme.audioGap

    function toggleAll() {
        const mute = anyAudible;
        audio.setMuted(mute);
        audio.setMicMuted(mute);
    }

    function deviceGlyph(node) {
        const name = audio.label(node).toLowerCase();
        if (/headphone|headset|earbud|earphone|airpod/.test(name)) return Icons.cp(0xF02CB);
        if (/bluetooth/.test(name)) return Icons.bluetooth;
        if (/hdmi|display/.test(name)) return Icons.monitor;
        return Icons.cp(0xF04C3);
    }

    function loudness() {
        if (!audio.ready) return "No output device";
        if (audio.muted) return "Muted";
        const v = outputVolume.liveValue;
        if (v === 0) return "Silenced";
        if (v >= 100) return "Concert hall";
        if (v >= 85) return "Party mode";
        if (v >= 70) return "Cranked up";
        if (v >= 50) return "Steady groove";
        if (v >= 30) return "Easy listening";
        if (v >= 15) return "Murmur";
        return "Whisper";
    }

    // Native Tab and arrow/vim navigation share real control focus. The popup
    // scrolls focused controls into view; no second, invisible selection cursor.
    function controls(item, list) {
        for (let child of item.children) {
            if (!child.visible || !child.enabled) continue;
            if (child.activeFocusOnTab) list.push(child);
            else controls(child, list);
        }
        return list;
    }
    function moveFocus(direction) {
        const items = controls(panel, []);
        if (!items.length) return;
        const index = items.findIndex(item => item.activeFocus);
        // Begrenzen statt umlaufen -- die Referenz bleibt am Ende stehen.
        const next = Math.max(0, Math.min(items.length - 1, (index < 0 ? 0 : index) + direction));
        items[next].forceActiveFocus(Qt.TabFocusReason);
    }
    Keys.onPressed: event => {
        if (event.modifiers !== Qt.NoModifier) return;
        if ([Qt.Key_Up, Qt.Key_K, Qt.Key_Down, Qt.Key_J].includes(event.key)) {
            moveFocus(event.key === Qt.Key_Up || event.key === Qt.Key_K ? -1 : 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && closePopout) {
            closePopout(); event.accepted = true;
        }
    }

    Item {
        width: panel.rowWidth
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)
        Line {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.audio.muted ? Icons.volumeMuted : Icons.cp(0xF057E)
            font.pixelSize: Theme.audioHeroSize
            opacity: panel.audio.muted ? 0.5 : 1
        }
        Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Theme.audioGap
            anchors.right: powerSwitch.left
            anchors.rightMargin: Theme.audioRowPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(2 * Theme.audioScale)
            Line { width: parent.width; text: "Audio"; font.pixelSize: Theme.audioTitleSize; font.bold: true; elide: Text.ElideRight }
            Caption { width: parent.width; text: panel.loudness().toUpperCase(); font.letterSpacing: 1.2; elide: Text.ElideRight }
        }
        InteractiveSurface {
            id: powerSwitch
            objectName: "audioPower"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.round(Theme.audioSwitchHeight * 1.9) + Theme.audioRowGap * 2
            implicitHeight: Theme.audioSwitchHeight + Theme.audioRowGap * 2
            readonly property bool checked: panel.anyAudible
            color: "transparent"
            radius: Theme.radius
            border.width: activeFocus ? Theme.borderWidth : 0
            border.color: Theme.audioOutline
            accessibleRole: Accessible.CheckBox
            accessibleCheckable: true
            accessibleChecked: checked
            // Keep a focusable empty-state control so native popup focus always
            // has a real destination. Activation is a guarded no-op without nodes.
            accessibleName: panel.anyAudible ? "Mute audio and microphone" : "Unmute audio and microphone"
            onTriggered: panel.toggleAll()
            Keys.onEscapePressed: if (panel.closePopout) panel.closePopout()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_M) { panel.toggleAll(); event.accepted = true; }
            }
            HoverHandler { id: powerHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) powerSwitch.forceActiveFocus(Qt.MouseFocusReason) }
            TapHandler { onTapped: { powerSwitch.forceActiveFocus(Qt.MouseFocusReason); powerSwitch.activate(); } }
            Rectangle {
                anchors.centerIn: parent
                width: Math.round(Theme.audioSwitchHeight * 1.9)
                height: Theme.audioSwitchHeight
                radius: Theme.radius > 0 ? height / 2 : 0
                color: powerSwitch.checked ? Theme.audioSelected : "transparent"
                border.width: powerSwitch.checked ? 0 : Theme.borderWidth
                border.color: Theme.panelBorder
                Rectangle {
                    width: Math.round(parent.height * 0.72); height: width
                    radius: Theme.radius > 0 ? height / 2 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    x: powerSwitch.checked ? parent.width - width - (parent.height - height) / 2 : (parent.height - height) / 2
                    color: powerSwitch.checked ? Theme.readable(Theme.accent, Theme.audioSelected, 4.5) : Theme.audioSecondary
                    Behavior on x { NumberAnimation { duration: Theme.motionEffectsFast } }
                }
            }
            Controls.ToolTip.visible: powerHover.hovered
            Controls.ToolTip.text: Accessible.name
        }
    }

    Separator {}
    Column {
        width: panel.rowWidth
        spacing: Theme.audioRowGap
        Section { title: "OUTPUT"; value: Math.round(outputVolume.liveValue) + "%" }
        VolumeControl {
            id: outputVolume
            objectName: "audioOutput"
            width: panel.rowWidth
            accessibleName: "Output volume"
            enabled: panel.audio.ready
            value: panel.audio.volume
            maximum: panel.audio.maxVolume
            muted: panel.audio.muted
            onMoved: v => panel.audio.setVolume(v)
            onTriggered: panel.audio.toggleMute()
        }
        Repeater {
            model: panel.audio.sinks
            ActionRow {
                required property var modelData
                title: panel.audio.label(modelData)
                glyph: panel.deviceGlyph(modelData)
                current: modelData === panel.audio.sink
                accessibleName: "Output: " + title
                onTriggered: panel.audio.setSink(modelData)
                Keys.onPressed: event => panel.deviceKey(event, outputVolume)
            }
        }
    }

    Separator { visible: panel.hasInput || panel.audio.sources.length > 0 }
    Column {
        width: panel.rowWidth
        visible: panel.hasInput || panel.audio.sources.length > 0
        spacing: Theme.audioRowGap
        Section { title: "INPUT"; value: Math.round(inputVolume.liveValue) + "%" }
        VolumeControl {
            id: inputVolume
            objectName: "audioInput"
            width: panel.rowWidth
            accessibleName: "Microphone volume"
            enabled: panel.hasInput
            value: panel.audio.micVolume
            maximum: 100
            muted: panel.audio.micMuted
            showPeak: true
            peak: panel.audio.micPeak
            onMoved: v => panel.audio.setMicVolume(v)
            onTriggered: panel.audio.setMicMuted(!panel.audio.micMuted)
        }
        Repeater {
            model: panel.audio.sources
            ActionRow {
                required property var modelData
                title: panel.audio.label(modelData)
                glyph: Icons.cp(0xF036C)
                current: modelData === panel.audio.source
                accessibleName: "Input: " + title
                onTriggered: panel.audio.setSource(modelData)
                Keys.onPressed: event => panel.deviceKey(event, inputVolume)
            }
        }
    }

    Separator { visible: panel.audio.appStreams.length > 0 }
    Column {
        visible: panel.audio.appStreams.length > 0
        width: panel.rowWidth
        spacing: Theme.audioRowPadding
        Section { title: "SOURCES" }
        Repeater {
            model: panel.audio.appStreams
            VolumeControl {
                required property var modelData
                width: panel.rowWidth
                title: panel.audio.label(modelData)
                accessibleName: title + " volume"
                value: panel.audio.streamVolume(modelData)
                maximum: panel.audio.maxVolume
                muted: !!modelData.audio?.muted
                onMoved: v => panel.audio.setStreamVolume(modelData, v)
                onTriggered: panel.audio.toggleStreamMute(modelData)
            }
        }
    }

    Separator { visible: routes.visible }
    Column {
        id: routes
        visible: panel.audio.routes.length > 0 && panel.audio.routeSinks.length > 1
        width: panel.rowWidth
        spacing: Theme.audioRowGap
        Section { title: "OUTPUT ROUTES" }
        Repeater {
            model: panel.audio.routeSinks.length > 1 ? panel.audio.routes : []
            ActionRow {
                required property var modelData
                title: modelData.name
                detail: modelData.sinkLabel + "  ›"
                accessibleName: "Route " + title
                accessibleDescription: "Current output: " + modelData.sinkLabel + ". Activate to switch."
                onTriggered: panel.audio.cycleRoute(modelData)
            }
        }
    }

    Separator { visible: codecs.visible }
    Column {
        id: codecs
        visible: panel.audio.btDa
        width: panel.rowWidth
        spacing: Theme.audioRowGap
        Section { title: "BLUETOOTH CODEC" }
        Caption { width: parent.width; text: panel.audio.btGeraet; elide: Text.ElideRight }
        Line {
            visible: panel.audio.btTelefonie
            width: parent.width
            text: "Telephony (" + panel.audio.btCodec + ") — narrowband, with microphone"
            wrapMode: Text.WordWrap
            color: Theme.readable(Theme.yellow, Theme.bg, 4.5)
        }
        Repeater {
            model: panel.audio.btTelefonie ? [] : panel.audio.btCodecs
            ActionRow {
                required property var modelData
                title: modelData.codec
                current: modelData.profil === panel.audio.btAktiv
                accessibleName: "Use " + title + " Bluetooth codec"
                onTriggered: panel.audio.setzeCodec(modelData.profil)
            }
        }
        ActionRow {
            visible: panel.audio.btSchlechter
            title: "Better codec available"
            detail: panel.audio.btCodecs.length ? panel.audio.btCodecs[0].codec : ""
            accessibleName: title + ": " + detail
            onTriggered: panel.audio.setzeCodec(panel.audio.btBeste)
        }
    }

    function deviceKey(event, control) {
        if (event.modifiers !== Qt.NoModifier) return;
        if ([Qt.Key_Left, Qt.Key_H, Qt.Key_Right, Qt.Key_L].includes(event.key)) {
            control.adjust(event.key === Qt.Key_Left || event.key === Qt.Key_H ? -1 : 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_M) { control.activate(); event.accepted = true; }
    }

    component Caption: Line {
        color: Theme.audioSecondary
        font.pixelSize: Theme.audioCaptionSize
        font.bold: true
    }
    component Separator: Rectangle {
        width: panel.rowWidth
        height: Math.max(1, Theme.borderWidth)
        color: Theme.mix(Theme.bg, Theme.fg, 0.18)
    }
    component Section: Item {
        property string title: ""
        property string value: ""
        width: panel.rowWidth
        implicitHeight: sectionTitle.implicitHeight
        Caption { id: sectionTitle; text: parent.title; anchors.left: parent.left; font.letterSpacing: 1.2 }
        Caption { text: parent.value; anchors.right: parent.right; anchors.rightMargin: Theme.audioRowGap }
    }
    component ActionRow: InteractiveSurface {
        id: action
        property string title: ""
        property string detail: ""
        property string glyph: ""
        property bool current: false
        width: panel.rowWidth
        implicitHeight: Math.max(labels.implicitHeight, glyphText.implicitHeight) + Theme.audioRowPadding
        color: activeFocus ? Theme.audioHover : current ? Theme.audioSelected : "transparent"
        radius: Theme.radius
        border.width: activeFocus ? Theme.borderWidth : 0
        border.color: Theme.audioOutline
        accessibleSelected: current
        accessibleName: title
        accessibleDescription: detail
        Line {
            id: glyphText
            x: Theme.audioRowGap
            anchors.verticalCenter: parent.verticalCenter
            width: action.glyph ? Theme.audioIconSlot : 0
            text: action.glyph
            font.pixelSize: Theme.audioTitleSize
            horizontalAlignment: Text.AlignHCenter
        }
        Column {
            id: labels
            x: Theme.audioRowGap + (action.glyph ? Theme.audioIconSlot + Theme.audioControlGap : 0)
            width: parent.width - x - Theme.audioRowGap
            anchors.verticalCenter: parent.verticalCenter
            Line { width: parent.width; text: action.title; font.bold: action.current; elide: Text.ElideRight }
            Caption { width: parent.width; text: action.detail; visible: text !== ""; elide: Text.ElideRight }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) action.forceActiveFocus(Qt.MouseFocusReason) }
        TapHandler { onTapped: { action.forceActiveFocus(Qt.MouseFocusReason); action.activate(); } }
    }
    component VolumeControl: InteractiveSurface {
        id: control
        property real value: 0
        property real maximum: 100
        property bool muted: false
        property string title: ""
        property bool showPeak: false
        property real peak: 0
        readonly property real liveValue: slider.liveValue
        readonly property real minimumValue: 0
        readonly property real maximumValue: maximum
        readonly property real stepSize: 5
        signal moved(real value)
        accessibleRole: Accessible.Slider
        Accessible.onIncreaseAction: adjust(1)
        Accessible.onDecreaseAction: adjust(-1)
        implicitHeight: body.implicitHeight + (title ? Theme.audioRowPadding : Theme.audioControlGap)
        color: activeFocus ? Theme.audioHover : "transparent"
        radius: Theme.radius
        border.width: activeFocus ? Theme.borderWidth : 0
        border.color: Theme.audioOutline
        function adjust(direction) { slider.commitStep(direction); }
        Keys.onPressed: event => panel.deviceKey(event, control)
        Column {
            id: body
            x: Theme.audioRowGap
            width: parent.width - Theme.audioRowGap * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round((control.showPeak ? 5 : 2) * Theme.audioScale)
            Item {
                visible: control.title !== ""
                width: parent.width
                implicitHeight: streamTitle.implicitHeight
                Line {
                    width: Theme.audioIconSlot
                    horizontalAlignment: Text.AlignHCenter
                    text: control.muted ? Icons.volumeMuted : Icons.volumeHigh
                    font.pixelSize: Theme.audioTitleSize
                    opacity: control.muted ? 0.5 : 1
                    TapHandler { onTapped: control.activate() }
                }
                Line {
                    id: streamTitle
                    x: Theme.audioIconSlot + Theme.audioControlGap
                    width: Math.max(0, parent.width - x - streamPercent.width - Theme.audioControlGap)
                    text: control.title
                    elide: Text.ElideRight
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: control.activate() }
                }
                Caption { id: streamPercent; anchors.right: parent.right; text: Math.round(control.liveValue) + "%" }
            }
            Ui.PanelSlider {
                id: slider
                width: parent.width
                implicitHeight: Theme.audioSliderHeight
                trackHeight: Theme.audioTrackHeight
                knobSize: Theme.audioKnobSize
                value: control.value
                maximum: control.maximum
                step: 5
                integer: true
                trackColor: Theme.mix(Theme.bg, Theme.fg, 0.18)
                fillColor: Theme.fg
                knobColor: Theme.fg
                opacity: control.muted || !control.enabled ? 0.5 : 1
                // The enclosing keyboard/AT target owns the entire row.
                Accessible.ignored: true
                bar: QtObject { property color background: Theme.bg; property color foreground: Theme.fg }
                onMoved: v => { control.forceActiveFocus(Qt.MouseFocusReason); control.moved(v); }
                onRightClicked: control.activate()
            }
            Rectangle {
                visible: control.showPeak
                width: parent.width
                height: Math.max(1, Math.round(5 * Theme.audioScale))
                color: Theme.mix(Theme.bg, Theme.fg, 0.18)
                opacity: control.muted ? 0.35 : 1
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, control.peak)); height: parent.height; color: Theme.fg
                    Behavior on width { NumberAnimation { duration: Theme.motionEffectsFast } }
                }
            }
        }
        HoverHandler { onHoveredChanged: if (hovered) control.forceActiveFocus(Qt.MouseFocusReason) }
    }
}
