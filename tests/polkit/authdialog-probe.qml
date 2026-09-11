import QtQuick
import Quickshell
import qs.Polkit
import qs.Common

FloatingWindow {
    id: test
    implicitWidth: Number(Quickshell.env("POLKIT_PREVIEW_WIDTH") || 800)
    implicitHeight: 600
    visible: true
    QtObject {
        id: first
        property string message: "Authorize a test operation"
        property string actionId: "org.nbshell.test"
        property var identities: []
        property var selectedIdentity: null
        property bool isCompleted: false
        property bool isResponseRequired: true
        property string inputPrompt: "Password:"
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool failed: false
        property int submits: 0
        property int cancels: 0
        signal authenticationFailed()
        function submit(value) { submits++; }
        function cancelAuthenticationRequest() { cancels++; isCompleted = true; }
    }
    QtObject {
        id: second
        property string message: "Second request"
        property string actionId: "org.nbshell.second"
        property var identities: []
        property var selectedIdentity: null
        property bool isCompleted: false
        property bool isResponseRequired: true
        property string inputPrompt: "Response:"
        property bool responseVisible: true
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool failed: false
        signal authenticationFailed()
        function submit(value) {}
        function cancelAuthenticationRequest() {}
    }
    AuthDialog { id: dialog; anchors.centerIn: parent; width: Math.min(520, parent.width - 32); height: Math.min(implicitHeight, parent.height - 32); flow: first }
    function compare(actual, expected) {
        if (actual !== expected) throw new Error("Mismatch: " + actual + " != " + expected);
    }
    function verify(value) { if (!value) throw new Error("Assertion failed"); }
    Timer {
        interval: 400; running: true
        onTriggered: {
            try {
                const cases = [test.test_mask_and_submit_once, test.test_flow_switch_clears_secret,
                    test.test_multi_step_and_retry, test.test_cancel_clears_and_completes,
                    test.test_prompt_and_identity_clear, test.test_completion_clear, test.test_wait_no_submission];
                for (const run of cases) { test.init(); run(); }
                test.init();
                first.isResponseRequired = false;
                wakePrompt.start();
                return;
            } catch (error) { console.error("POLKIT_DIALOG_TESTS_FAIL", error); }
            Qt.quit();
        }
    }
    Timer {
        id: wakePrompt
        interval: 50
        onTriggered: {
            first.isResponseRequired = true;
            focusCheck.start();
        }
    }
    Timer {
        id: focusCheck
        interval: 50
        onTriggered: {
            try {
                test.verify(dialog.responseField.activeFocus);
                console.info("POLKIT_DIALOG_TESTS_PASS 8");
                if (Quickshell.env("POLKIT_PREVIEW")) {
                    if (Quickshell.env("POLKIT_PREVIEW_LIGHT") === "1")
                        Theme.c = {mode: "light", background: "#eff1f5", foreground: "#4c4f69", accent: "#1e66f5", muted: "#9ca0b0", red: "#d20f39"};
                    capture.start();
                    return;
                }
            } catch (error) { console.error("POLKIT_DIALOG_TESTS_FAIL", error); }
            Qt.quit();
        }
    }
    Timer {
        id: capture
        interval: 300
        onTriggered: dialog.grabToImage(result => {
            result.saveToFile(Quickshell.env("POLKIT_PREVIEW"));
            Qt.quit();
        })
    }
    function init() {
        first.isCompleted = false; first.isResponseRequired = true;
        first.responseVisible = false; first.failed = false;
        first.submits = 0; first.cancels = 0; first.inputPrompt = "Password:";
        dialog.flow = first; dialog.resetInput();
    }
    function test_mask_and_submit_once() {
        verify(dialog.responseField.password);
        dialog.responseField.text = "synthetic-not-a-password";
        dialog.submit(); dialog.submit();
        compare(first.submits, 1); compare(dialog.responseField.text, "");
    }
    function test_flow_switch_clears_secret() {
        dialog.responseField.text = "synthetic";
        dialog.flow = second;
        compare(dialog.responseField.text, ""); verify(!dialog.responseField.password);
        dialog.flow = null;
        verify(!dialog.responding);
        dialog.submit();
        compare(first.submits, 0);
    }
    function test_multi_step_and_retry() {
        dialog.submit();
        first.isResponseRequired = false;
        first.isResponseRequired = true;
        verify(dialog.responding);
        first.failed = true; first.authenticationFailed();
        verify(dialog.responding); verify(!first.isCompleted);
    }
    function test_cancel_clears_and_completes() {
        dialog.responseField.text = "synthetic";
        dialog.cancelRequest();
        compare(first.cancels, 1); compare(dialog.responseField.text, "");
        verify(!dialog.responding);
    }
    function test_prompt_and_identity_clear() {
        dialog.responseField.text = "synthetic";
        first.inputPrompt = "Verification code:";
        compare(dialog.responseField.text, "");
        dialog.responseField.text = "synthetic";
        first.selectedIdentity = second;
        compare(dialog.responseField.text, "");
    }
    function test_completion_clear() {
        dialog.responseField.text = "synthetic";
        first.isCompleted = true;
        compare(dialog.responseField.text, "");
    }
    function test_wait_no_submission() {
        first.isResponseRequired = false;
        dialog.submit(); compare(first.submits, 0);
        dialog.cancelRequest(); compare(first.cancels, 1);
    }
}
