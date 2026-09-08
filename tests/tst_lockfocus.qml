import QtQuick
import QtTest
import "../shell/lock" as Lock

TestCase {
    name: "LockFocus"
    when: windowShown
    width: 800; height: 600

    Component {
        id: viewComponent
        Lock.LockView {
            width: 800; height: 600
            primary: false; previewMode: false
            username: "test"; wallpaper: ""
            background: "black"; foreground: "white"; muted: "gray"
            accent: "cyan"; danger: "red"; fontFamily: "monospace"
            dimOpacity: 0.5; hourFormat: "24h"
            reducedMotion: true; showSecondsRing: false
            authenticating: false; statusMessage: ""; statusError: false
            resetSerial: 0
        }
    }
    SignalSpy { id: submittedSpy; signalName: "submitted" }

    function test_password_focus_data() {
        return [{tag: "initial-primary", initial: true},
                {tag: "late-screen-assignment", initial: false}];
    }
    function test_password_focus(data) {
        const view = createTemporaryObject(viewComponent, this, {primary: data.initial});
        verify(view !== null);
        submittedSpy.target = view;
        submittedSpy.clear();
        wait(0);
        view.primary = true;
        wait(0);
        keyClick(Qt.Key_A);
        keyClick(Qt.Key_Return);
        tryCompare(submittedSpy, "count", 1);
        compare(submittedSpy.signalArguments[0][0], "a");
        submittedSpy.target = null;
    }
}
