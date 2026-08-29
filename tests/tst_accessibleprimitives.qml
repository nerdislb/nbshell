import QtQuick
import QtTest
import "../shell/Widgets" as Widgets

TestCase {
    id: root
    name: "AccessiblePrimitives"
    when: windowShown

    property int controlTriggers: 0
    property int actionTriggers: 0
    property int actionRightTriggers: 0
    property int rowTriggers: 0
    property int staticRowTriggers: 0

    Item {
        width: 600
        height: 200

        Widgets.ControlButton {
            id: control
            text: "Apply"
            onTriggered: root.controlTriggers += 1
        }

        Widgets.ActionButton {
            id: action
            x: 180
            text: "Save"
            onTriggered: root.actionTriggers += 1
            onRightTriggered: root.actionRightTriggers += 1
        }

        Widgets.PanelRow {
            id: row
            x: 320
            title: "Network"
            detail: "Connected securely"
            value: "Online"
            interactive: true
            onTriggered: root.rowTriggers += 1
        }

        Widgets.PanelRow {
            id: staticRow
            x: 320
            y: 60
            title: "Read-only status"
            detail: "No action available"
            onTriggered: root.staticRowTriggers += 1
        }

        Widgets.ControlButton {
            id: previewControl
            y: 120
            text: "Focus preview"
            interactive: false
            visualFocus: true
            accessibilityIgnored: true
        }
    }

    function cleanup() {
        controlTriggers = 0;
        actionTriggers = 0;
        actionRightTriggers = 0;
        rowTriggers = 0;
        staticRowTriggers = 0;
        control.enabled = true;
        control.interactive = true;
        control.selected = false;
        action.enabled = true;
        action.interactive = true;
        action.busy = false;
        row.enabled = true;
        row.interactive = true;
        row.selected = false;
    }

    function test_accessible_metadata() {
        compare(control.Accessible.role, Accessible.Button);
        compare(control.Accessible.name, "Apply");
        compare(control.Accessible.focusable, true);
        compare(action.Accessible.name, "Save");
        compare(row.Accessible.name, "Network");
        compare(row.Accessible.description, "Connected securely; Online");
        compare(staticRow.Accessible.role, Accessible.StaticText);
        compare(staticRow.Accessible.focusable, false);
        compare(previewControl.Accessible.ignored, true);
        compare(previewControl.Accessible.focused, false);
        compare(previewControl.border.width, 1);
    }

    function test_keyboard_activation() {
        control.forceActiveFocus();
        tryCompare(control, "activeFocus", true);
        keyClick(Qt.Key_Space);
        compare(controlTriggers, 1);

        action.forceActiveFocus();
        tryCompare(action, "activeFocus", true);
        keyClick(Qt.Key_Return);
        compare(actionTriggers, 1);

        row.forceActiveFocus();
        tryCompare(row, "activeFocus", true);
        keyClick(Qt.Key_Enter);
        compare(rowTriggers, 1);
    }

    function test_accessibility_press_action() {
        control.Accessible.pressAction();
        action.Accessible.pressAction();
        row.Accessible.pressAction();
        compare(controlTriggers, 1);
        compare(actionTriggers, 1);
        compare(rowTriggers, 1);
    }

    function test_disabled_or_busy_controls_do_not_activate() {
        control.enabled = false;
        control.Accessible.pressAction();
        compare(controlTriggers, 0);

        action.busy = true;
        action.Accessible.pressAction();
        compare(actionTriggers, 0);
    }

    function test_selected_control_keeps_visible_focus_border() {
        control.selected = true;
        control.forceActiveFocus();
        tryCompare(control, "activeFocus", true);
        compare(control.border.width, 1);

        action.forceActiveFocus();
        tryCompare(action, "activeFocus", true);
        compare(control.border.width, 0);

        row.selected = true;
        row.forceActiveFocus();
        tryCompare(row, "activeFocus", true);
        compare(row.border.width, 1);
    }

    function test_non_interactive_contract_blocks_all_activation_paths() {
        control.interactive = false;
        control.Accessible.pressAction();
        mouseClick(control, control.width / 2, control.height / 2, Qt.LeftButton);
        compare(controlTriggers, 0);

        action.interactive = false;
        mouseClick(action, action.width / 2, action.height / 2, Qt.RightButton);
        compare(actionTriggers, 0);
        compare(actionRightTriggers, 0);

        staticRow.Accessible.pressAction();
        compare(staticRowTriggers, 0);
    }

    function test_key_auto_repeat_is_ignored() {
        const repeated = { "isAutoRepeat": true, "accepted": false };
        control.activateFromKey(repeated);
        compare(controlTriggers, 0);
        compare(repeated.accepted, true);

        const firstPress = { "isAutoRepeat": false, "accepted": false };
        control.activateFromKey(firstPress);
        compare(controlTriggers, 1);
        compare(firstPress.accepted, true);
    }
}
