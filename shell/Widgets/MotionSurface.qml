import QtQuick
import qs.Common

// Panel surface with a short, GPU-composited lifecycle. It animates only
// opacity and scale, never paints continuously, and can delay the owner's
// visibility change long enough to show a real exit transition.
PanelSurface {
    id: root

    property bool motionEnabled: true
    // PopupWindow children remain logically visible while their Wayland window
    // is unmapped. Those owners prepare and start motion explicitly after their
    // final geometry is locked, avoiding an invisible startup animation.
    property bool autoEnter: true
    property bool closing: false
    property var closeCallback: null
    property real enterOffsetY: 0
    property real visualOffsetY: 0
    property bool transitionEnabled: true
    property int entryToken: 0

    function enter() {
        const token = ++entryToken;
        closing = false;
        closeTimer.stop();
        closeCallback = null;
        transitionEnabled = false;
        if (!motionEnabled || Theme.reducedMotion) {
            opacity = 1;
            scale = 1;
            visualOffsetY = 0;
            Qt.callLater(() => {
                if (root.entryToken === token)
                    root.transitionEnabled = true;
            });
            return;
        }
        opacity = 0;
        scale = Theme.motionEnterScale;
        visualOffsetY = enterOffsetY;
        Qt.callLater(() => {
            if (root.entryToken !== token)
                return;
            root.transitionEnabled = true;
            root.opacity = 1;
            root.scale = 1;
            root.visualOffsetY = 0;
        });
    }

    function dismiss(callback) {
        if (closing)
            return;
        ++entryToken;
        transitionEnabled = true;
        visualOffsetY = 0;
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

    onVisibleChanged: if (autoEnter && visible) enter()
    Component.onCompleted: if (autoEnter && visible) enter()

    transform: Translate {
        y: root.visualOffsetY
    }

    Behavior on opacity {
        enabled: root.transitionEnabled
        NumberAnimation {
            duration: root.closing ? Theme.motionExit : Theme.motionEnter
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.closing ? Theme.motionCurveStandard : Theme.motionCurveEnter
        }
    }
    Behavior on scale {
        enabled: root.transitionEnabled
        NumberAnimation {
            duration: root.closing ? Theme.motionExit : Theme.motionEnter
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.closing ? Theme.motionCurveStandard : Theme.motionCurveEnter
        }
    }
    Behavior on visualOffsetY {
        enabled: root.transitionEnabled
        NumberAnimation {
            duration: Theme.motionEnter
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.motionCurveEnter
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
