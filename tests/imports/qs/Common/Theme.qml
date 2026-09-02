pragma Singleton

import QtQuick

QtObject {
    readonly property string fontFamily: "monospace"
    readonly property int fontSize: 14
    readonly property int fontCaption: 13
    readonly property int fontBody: 15
    readonly property int fontSubtitle: 16
    readonly property int fontTitle: 17
    readonly property int fontHeading: 19
    readonly property int fontDisplay: 26
    readonly property real cellW: 8
    readonly property real cellH: 18
    readonly property real spaceXs: 4
    readonly property real spaceSm: 6
    readonly property real spaceMd: 8
    readonly property real spaceLg: 12
    readonly property real spaceXl: 16
    readonly property real controlHeight: 28
    readonly property real rowHeight: 34
    readonly property real panelPadding: 16
    readonly property real barIconCanvas: 18
    readonly property real barIconSlot: 20
    readonly property real barHeight: 28
    readonly property real uiScale: 1
    readonly property int radius: 2
    readonly property int borderWidth: 1
    readonly property int motionFast: 0
    readonly property int motionEffectsFast: 0
    readonly property int motionEffectsDefault: 0
    readonly property int motionSpatialFast: 0
    readonly property int motionLoopFast: 1
    readonly property int motionLoopSlow: 1
    readonly property int motionAttention: 0
    readonly property bool reducedMotion: true
    readonly property color bg: "#101010"
    readonly property color fg: "#f0f0f0"
    readonly property color fgDim: "#a0a0a0"
    readonly property color muted: "#707070"
    readonly property color red: "#ff6060"
    readonly property color accent: "#60a0ff"
    readonly property color focusBorder: "#80b8ff"
    readonly property color hover: "#303030"
    readonly property color panelSurfaceRaised: "#202020"
    readonly property color panelSurface: bg
    readonly property color panelBorder: fgDim
    readonly property color textFieldSelection: selectedSurface(accent)
    readonly property color textFieldSelectedText: fg
    readonly property real controlDisabledOpacity: 0.45

    function alpha(color, value) { return Qt.rgba(color.r, color.g, color.b, value); }
    function mix(base, tone, amount) {
        return Qt.rgba(
            base.r + (tone.r - base.r) * amount,
            base.g + (tone.g - base.g) * amount,
            base.b + (tone.b - base.b) * amount,
            1);
    }
    function selectedSurface(tone) { return mix(bg, tone ?? accent, 0.22); }
    function selectedForeground(tone) { return fg; }
    function readable(tone, surface, ratio) { return tone; }
    function controlFill(hot, selected, pressed) {
        if (pressed) return mix(bg, accent, 0.30);
        if (selected) return selectedSurface(accent);
        if (hot) return hover;
        return panelSurfaceRaised;
    }
    function controlBorder(hot, selected, urgent) {
        if (urgent) return red;
        if (hot) return accent;
        return fgDim;
    }
    function controlBorderWidth(hot, selected, urgent) { return selected && !urgent ? 0 : borderWidth; }
    function textFieldFill(hot, focused, readOnly) {
        if (readOnly) return bg;
        return controlFill(hot || focused, false, false);
    }
    function textFieldBorder(hot, focused, readOnly) {
        if (focused) return focusBorder;
        if (readOnly) return panelBorder;
        return controlBorder(hot, false, false);
    }
}
