import QtQuick
import qs.Common
import qs.Widgets
import "Curve.js" as Curve

Item {
    id: root
    property var curve: Curve.presetForScale(1)
    property real maximum: 1
    signal adjusted(int handle, real value)
    // Graph coordinates are domain-specific; chrome uses Theme geometry.
    implicitHeight: Theme.cellH * 12
    readonly property real pad: Theme.controlHeight
    readonly property real plotWidth: Math.max(1, width - 2 * pad)
    readonly property real plotHeight: Math.max(1, height - 2 * pad)
    onCurveChanged: graph.requestPaint()
    onMaximumChanged: graph.requestPaint()
    Connections {
        target: Theme
        function onCChanged() { graph.requestPaint(); }
    }
    Canvas {
        id: graph
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Theme.panelBorder;
            ctx.lineWidth = Theme.borderWidth;
            for (let i = 0; i <= 4; i++) {
                ctx.beginPath(); ctx.moveTo(root.pad, root.pad + root.plotHeight * i / 4);
                ctx.lineTo(width - root.pad, root.pad + root.plotHeight * i / 4); ctx.stroke();
            }
            const samples = Curve.points(root.curve);
            ctx.strokeStyle = Theme.accent;
            ctx.lineWidth = Theme.borderWidth * 2;
            ctx.beginPath();
            for (let x = 0; x <= 160; x++) {
                const gain = Curve.sampledGain(root.curve, x / 40, samples);
                const px = root.pad + root.plotWidth * x / 160;
                const py = height - root.pad - root.plotHeight * gain / root.maximum;
                if (x === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
            }
            ctx.stroke();
        }
    }
    Repeater {
        model: 4
        ControlButton {
            id: handle
            required property int index
            property real initial: 0
            objectName: "curveHandle" + index
            text: ["P", "S", "E", "F"][index]
            accessibleName: ["Precision", "Acceleration start", "Acceleration end", "Fast swipes"][index]
            readonly property bool horizontal: index === 1 || index === 2
            readonly property real value: [root.curve.precision, root.curve.start, root.curve.end, root.curve.fast][index]
            x: root.pad + root.plotWidth * (index === 0 ? 0 : index === 3 ? 1 : value / 4) - width / 2
            y: root.height - root.pad - root.plotHeight * (index === 0 ? value : index === 3 ? value : Curve.sampledGain(root.curve, value)) / root.maximum - height / 2
            selected: activeFocus || drag.active
            Keys.onPressed: event => {
                let direction = [Qt.Key_Right, Qt.Key_Up].indexOf(event.key) >= 0 ? 1 : [Qt.Key_Left, Qt.Key_Down].indexOf(event.key) >= 0 ? -1 : 0;
                if (direction) {
                    root.adjusted(index, value + direction * (horizontal ? 0.04 : 0.001) * (event.modifiers & Qt.ShiftModifier ? 10 : 1));
                    event.accepted = true;
                }
            }
            DragHandler {
                id: drag
                target: null
                onActiveChanged: if (active) { handle.initial = handle.value; handle.forceActiveFocus(); }
                onTranslationChanged: if (active) root.adjusted(handle.index, handle.initial + (handle.horizontal ? translation.x / root.plotWidth * 4 : -translation.y / root.plotHeight * root.maximum))
            }
        }
    }
    Line { anchors.left: parent.left; anchors.bottom: parent.bottom; text: "Slow / precise"; color: Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5) }
    Line { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "Fast swipes →"; color: Theme.readable(Theme.fgDim, Theme.panelSurface, 4.5) }
}
