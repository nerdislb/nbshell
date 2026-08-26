import QtQuick
import qs.Common

// Panel surface with a short, GPU-composited lifecycle. It animates only
// opacity and scale, never paints continuously, and can delay the owner's
// visibility change long enough to show a real exit transition.
PanelSurface {
    id: root

    property bool motionEnabled: true
    property bool closing: false
    property var closeCallback: null

    function enter() {
        closing = false;
        closeTimer.stop();
        if (!motionEnabled || Theme.reducedMotion) {
            opacity = 1;
            scale = 1;
            return;
        }
        opacity = 0;
        scale = Theme.motionEnterScale;
        Qt.callLater(() => {
            root.opacity = 1;
            root.scale = 1;
        });
    }

    function dismiss(callback) {
        if (closing)
            return;
        if (!motionEnabled || Theme.reducedMotion) {
            if (callback) callback();
            return;
        }
        closing = true;
        closeCallback = callback;
        opacity = 0;
        scale = 0.99;
        closeTimer.restart();
    }

    onVisibleChanged: if (visible) enter()
    Component.onCompleted: if (visible) enter()

    Behavior on opacity {
        NumberAnimation {
            duration: root.closing ? Theme.motionExit : Theme.motionEnter
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.closing ? Theme.motionCurveStandard : Theme.motionCurveEnter
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: root.closing ? Theme.motionExit : Theme.motionEnter
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.closing ? Theme.motionCurveStandard : Theme.motionCurveEnter
        }
    }
    Timer {
        id: closeTimer
        interval: Math.max(1, Theme.motionExit)
        onTriggered: {
            const callback = root.closeCallback;
            root.closeCallback = null;
            root.closing = false;
            if (callback) callback();
        }
    }
}
