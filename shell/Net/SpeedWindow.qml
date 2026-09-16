import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Widgets/FocusScroll.js" as FocusScroll

// Gauge geometry adapted from Omarchy Quattro 6ea3215 SpeedTestOverlay.qml.
// MIT notice: LICENSES/THIRD_PARTY_MIT.md. Native batch backend and extras retained.
PanelWindow {
    id: root

    property var result: null
    property bool running: false
    property bool cancelled: false
    property bool pendingRun: false
    property var closeDone: null
    property bool motionClosed: false
    property real fullScale: {
        const stored = Number(Config.value("speedScale", 100));
        return Number.isFinite(stored) && stored > 0 ? stored : 100;
    }
    readonly property bool valid: result !== null && result.ok === true
    readonly property string error: result !== null && !valid ? String(result.grund || "Speed test failed") : ""
    readonly property real gaugeGap: pixels(48)
    readonly property real dialDiameter: Math.min(pixels(210), Math.max(1, (box.width - gaugeGap) / 2))
    readonly property color onScrim: Theme.fg
    readonly property color onScrimDim: Theme.fgDim
    readonly property color gaugeAccent: Theme.readable(Theme.accent, Theme.bg, 3)
    readonly property string unit: "Mbit/s"

    // Attributed upstream gauge geometry, scaled with the existing menu rem.
    function pixels(value) {
        return Math.round(value * Theme.menuScale);
    }
    function start() {
        if (running || !Runtime.speedOpen)
            return;
        if (retry.activeFocus)
            input.forceActiveFocus();
        cancelled = false;
        pendingRun = false;
        result = null;
        running = true;
        proc.running = true;
    }
    function close() {
        Runtime.speedOpen = false;
    }
    function finishClose() {
        if (motionClosed && !running && closeDone) {
            const done = closeDone;
            closeDone = null;
            done();
        }
    }
    function requestClose(done) {
        closeDone = done;
        pendingRun = false;
        cancelled = true;
        if (proc.running)
            proc.signal(15);
        box.dismiss(() => {
            motionClosed = true;
            finishClose();
        });
    }
    function requestOpen() {
        closeDone = null;
        motionClosed = false;
        box.enter();
        input.forceActiveFocus();
        if (running)
            pendingRun = true;
        else
            start();
    }
    function complete(text, code) {
        running = false;
        if (!cancelled && Runtime.speedOpen) {
            try {
                const data = JSON.parse(text);
                if (code !== 0 || !data || typeof data !== "object")
                    throw new Error();
                if (data.ok === true) {
                    if (![data.down, data.up, data.ping].every(value => typeof value === "number" && Number.isFinite(value) && value >= 0))
                        throw new Error();
                    result = {
                        ok: true,
                        down: data.down,
                        up: data.up,
                        ping: data.ping,
                        server: String(data.server || "?")
                    };
                    const peak = Math.max(data.down, data.up);
                    if (peak > fullScale) {
                        fullScale = Math.ceil(peak / 50) * 50;
                        Config.set("speedScale", fullScale);
                    }
                } else
                    result = {
                        ok: false,
                        grund: String(data.grund || "Speed test failed")
                    };
            } catch (error) {
                result = {
                    ok: false,
                    grund: "Speed test returned an invalid response"
                };
            }
        }
        if (pendingRun && Runtime.speedOpen) {
            pendingRun = false;
            Qt.callLater(start);
        } else
            finishClose();
    }
    function reveal(item) {
        const point = item.mapToItem(content, 0, 0);
        viewport.contentY = FocusScroll.contentYForFocus(point.y, item.height, viewport.contentY, viewport.height, viewport.contentHeight, Theme.spaceXs);
    }
    function rate(value) {
        return value >= 1e6 ? value.toExponential(2) : value.toLocaleString(Qt.locale(), 'f', 1);
    }

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"
    WlrLayershell.namespace: "nbshell:speedtest"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.speedOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    Component.onCompleted: {
        input.forceActiveFocus();
        start();
    }
    Component.onDestruction: if (proc.running)
        proc.signal(15)

    Process {
        id: proc
        command: ["bash", Qt.resolvedUrl("../scripts/speedtest.sh").toString().replace("file://", "")]
        stdout: StdioCollector {
            id: output
            waitForEnd: true
        }
        onStarted: if (root.cancelled)
            proc.signal(15)
        onExited: (code, status) => root.complete(output.text, code)
    }

    Rectangle {
        anchors.fill: parent
        // Unlike upstream's fixed black/white palette this also supports light themes.
        color: Theme.alpha(Theme.bg, 0.90)
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }
    FocusScope {
        id: keys
        anchors.fill: parent
        focus: true
        Item {
            id: input
            focus: true
        }
        Keys.onEscapePressed: event => {
            root.close();
            event.accepted = true;
        }
        Keys.onPressed: event => {
            if (event.modifiers !== Qt.NoModifier)
                return;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (!event.isAutoRepeat)
                    root.start();
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, viewport.contentY + (event.key === Qt.Key_PageDown ? viewport.height : -viewport.height)));
                event.accepted = true;
            }
        }
        MotionSurface {
            id: box
            anchors.centerIn: parent
            width: Math.min(root.width - Theme.menuInset * 2, root.pixels(468))
            height: Math.min(root.height - Theme.menuInset * 2, content.height)
            color: "transparent"
            border.width: 0
            MouseArea {
                anchors.fill: parent
            }
            Flickable {
                id: viewport
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
                Column {
                    id: content
                    width: viewport.width
                    spacing: Theme.spaceXl
                    Line {
                        id: title
                        width: parent.width
                        text: root.valid ? root.result.server : "Internet speed test"
                        color: root.onScrimDim
                        font.pixelSize: Theme.fontCaption
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WrapAnywhere
                    }
                    Row {
                        spacing: root.gaugeGap
                        SpeedDial {
                            id: downDial
                            label: "DOWNLOAD"
                            value: root.valid ? root.result.down : 0
                        }
                        SpeedDial {
                            id: upDial
                            label: "UPLOAD"
                            value: root.valid ? root.result.up : 0
                        }
                    }
                    Line {
                        id: facts
                        width: parent.width
                        text: "Ping  " + (root.valid && root.result.ping > 0 && root.result.ping < 5000 ? root.result.ping.toLocaleString(Qt.locale(), 'f', 1) + " ms" : "—") + "   ·   Scale  " + root.rate(root.fullScale) + " Mbit/s"
                        color: root.onScrimDim
                        font.pixelSize: Theme.fontCaption
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        id: actions
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spaceMd
                        ControlButton {
                            id: retry
                            text: root.running ? "Measuring…" : "Run Again"
                            accessibleName: "Measure again"
                            enabled: !root.running
                            onTriggered: root.start()
                            onActiveFocusChanged: if (activeFocus)
                                root.reveal(retry)
                        }
                        ControlButton {
                            id: closeButton
                            text: "Close"
                            accessibleName: "Close speed test"
                            onTriggered: root.close()
                            onActiveFocusChanged: if (activeFocus)
                                root.reveal(closeButton)
                        }
                    }
                    Line {
                        id: errorLabel
                        width: parent.width
                        visible: text !== ""
                        text: root.error
                        color: Theme.readable(Theme.red, Theme.bg, 4.5)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WrapAnywhere
                    }
                    Line {
                        id: footer
                        width: parent.width
                        text: "Enter / Space measure · Esc close"
                        color: root.onScrimDim
                        font.pixelSize: Theme.fontCaption
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
    // One floating cluster dial: an open 270° scale with the gap at the
    // bottom, a faint tick ring, a glowing accent value arc, a hubless needle
    // that fades toward the pivot, and a digital readout in the middle. All
    // writes to the needle funnel through `shown`. Only actual final values
    // animate; the batch backend has neither live samples nor a startup sweep.
    component SpeedDial: Item {
        id: dial

        required property string label
        required property real value

        readonly property real diameter: root.dialDiameter
        readonly property real compactScale: Math.min(1, diameter / root.pixels(210))
        function pixels(value) {
            return Math.max(1, Math.round(root.pixels(value) * compactScale));
        }
        // 0° = 3 o'clock, increasing clockwise (PathAngleArc's convention).
        readonly property real dialStart: 135
        readonly property real dialSweep: 270
        readonly property int tickCount: 46
        readonly property real arcWidth: dial.pixels(4)
        readonly property real arcRadius: diameter / 2 - arcWidth
        readonly property color trackColor: Theme.alpha(Theme.fg, 0.14)
        readonly property color minorTickColor: Theme.alpha(Theme.fg, 0.12)
        readonly property color majorTickColor: Theme.alpha(Theme.fg, 0.3)
        // Unknown readings sit dimmed; a measured zero is still a valid result.
        readonly property bool engaged: root.valid

        property real shown: value
        readonly property real reading: shown
        readonly property real fullScale: root.fullScale
        readonly property real fraction: fullScale > 0 ? Math.max(0, Math.min(1, shown / fullScale)) : 0
        readonly property bool arcVisible: fraction > 0.004

        width: diameter
        height: diameter
        opacity: engaged ? 1 : 0.5

        Accessible.role: Accessible.StaticText
        Accessible.name: label + ": " + (root.valid ? root.rate(value) + " " + root.unit : "Not measured")
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.motionEffectsDefault
            }
        }
        Behavior on shown {
            NumberAnimation {
                duration: Theme.motionSpatialSlow
                easing.type: Easing.OutCubic
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Track: the full scale, always visible, dim.
            ShapePath {
                strokeWidth: dial.arcWidth
                strokeColor: dial.trackColor
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.arcRadius
                    radiusY: dial.arcRadius
                    startAngle: dial.dialStart
                    sweepAngle: dial.dialSweep
                }
            }

            // Soft under-glow beneath the value arc, standing in for the backlit
            // ring of a real cluster. Both arcs go transparent at rest, or their
            // round caps would leave a stray dot at the foot of the scale.
            ShapePath {
                strokeWidth: dial.arcWidth * 3
                strokeColor: dial.arcVisible ? Theme.alpha(root.gaugeAccent, 0.18) : "transparent"
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.arcRadius
                    radiusY: dial.arcRadius
                    startAngle: dial.dialStart
                    sweepAngle: dial.dialSweep * dial.fraction
                }
            }

            // Value: fills behind the needle.
            ShapePath {
                strokeWidth: dial.arcWidth
                strokeColor: dial.arcVisible ? root.gaugeAccent : "transparent"
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: dial.width / 2
                    centerY: dial.height / 2
                    radiusX: dial.arcRadius
                    radiusY: dial.arcRadius
                    startAngle: dial.dialStart
                    sweepAngle: dial.dialSweep * dial.fraction
                }
            }
        }

        // Faint tick ring just inside the arc; every fifth tick is a major.
        Repeater {
            model: dial.tickCount

            Item {
                required property int index
                readonly property bool major: index % 5 === 0

                anchors.fill: parent
                rotation: dial.dialStart + (index / (dial.tickCount - 1)) * dial.dialSweep - 270

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: dial.arcWidth * 2 + (parent.major ? 0 : dial.pixels(2))
                    width: parent.major ? Math.max(2, dial.pixels(2)) : 1
                    height: parent.major ? dial.pixels(10) : dial.pixels(6)
                    radius: width / 2
                    color: parent.major ? dial.majorTickColor : dial.minorTickColor
                }
            }
        }

        // Hubless needle: a slender sliver that fades out toward the pivot, so
        // it reads as floating like the rest of the cluster.
        Item {
            anchors.fill: parent
            rotation: dial.dialStart + dial.fraction * dial.dialSweep - 270

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: dial.arcWidth * 2 + dial.pixels(10)
                width: Math.max(2, dial.pixels(3))
                height: dial.diameter * 0.32
                radius: width / 2

                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: root.gaugeAccent
                    }
                    GradientStop {
                        position: 0.55
                        color: root.gaugeAccent
                    }
                    GradientStop {
                        position: 1.0
                        color: "transparent"
                    }
                }
            }
        }

        Column {
            id: readout
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: dial.pixels(14)
            spacing: 0

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                width: dial.diameter * 0.7
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.Fit
                minimumPixelSize: Theme.fontBody
                text: root.valid ? root.rate(dial.reading) : "—"
                color: root.onScrim
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(Theme.fontBody, Math.round(Theme.fontDisplay * dial.compactScale))
                font.bold: true
            }

            Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.unit
                color: root.onScrimDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontCaption
            }
        }

        // The 90° gap at the bottom of the scale is where a cluster prints its
        // unit; here it names the direction.
        Text {
            id: directionLabel
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: dial.label
            color: root.onScrimDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontCaption
            font.bold: true
            font.letterSpacing: 1.5
        }
    }
}
