import QtQuick
import QtTest
import "../shell/Widgets" as Widgets
import "../shell/Widgets/FocusScroll.js" as FocusScroll

TestCase {
    id: root
    name: "AccessiblePrimitives"
    when: windowShown

    property int controlTriggers: 0
    property int actionTriggers: 0
    property int actionRightTriggers: 0
    property int rowTriggers: 0
    property int staticRowTriggers: 0
    property int sliderMovedValue: -1

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
            width: 280
            height: implicitHeight
            title: "Network"
            detail: "Connected securely"
            value: "Online"
            trailingInset: 80
            pointerActivationExclusion: rowExclusion
            pointerActivationExclusionEnabled: true
            interactive: true
            onTriggered: root.rowTriggers += 1

            Item {
                id: rowExclusionContainer
                x: row.width - width
                width: 80
                height: row.height

                Widgets.ActionButton {
                    id: rowExclusion
                    anchors.fill: parent
                    text: "Remove"
                }
            }
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

        Widgets.LevelBar {
            id: slider
            x: 460
            y: 60
            value: 50
            keyboardFocusable: true
            accessibleName: "Output volume"
            onMoved: value => root.sliderMovedValue = value
        }

        Widgets.LevelBar {
            id: passiveMeter
            x: 460
            y: 120
            value: 25
        }
    }

    function cleanup() {
        controlTriggers = 0;
        actionTriggers = 0;
        actionRightTriggers = 0;
        rowTriggers = 0;
        staticRowTriggers = 0;
        sliderMovedValue = -1;
        control.enabled = true;
        control.interactive = true;
        row.activationBlocked = false;
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
        compare(control.textColor, "#f0f0f0");
        compare(action.Accessible.name, "Save");
        compare(row.Accessible.name, "Network");
        compare(row.Accessible.description, "Connected securely; Online");
        compare(row.contentLeftPadding, 16);
        compare(row.trailingInset, 80);
        compare(row.hovered, false);
        compare(staticRow.Accessible.role, Accessible.StaticText);
        compare(staticRow.Accessible.focusable, false);
        compare(previewControl.Accessible.ignored, true);
        compare(previewControl.Accessible.focused, false);
        compare(previewControl.border.width, 1);
        compare(slider.Accessible.role, Accessible.Slider);
        compare(slider.Accessible.name, "Output volume");
        compare(slider.Accessible.focusable, true);
        compare(slider.Accessible.ignored, false);
        compare(slider.minimumValue, 0);
        compare(slider.maximumValue, 100);
        compare(slider.stepSize, 5);
        compare(slider.asLine, true);
        compare(passiveMeter.activeFocusOnTab, false);
        compare(passiveMeter.Accessible.ignored, true);
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

    function test_panel_row_pointer_exclusion() {
        compare(row.width, 280);
        compare(rowExclusionContainer.x, 200);
        compare(rowExclusion.x, 0);
        compare(rowExclusion.width, 80);
        compare(rowExclusion.y, 0);
        compare(rowExclusion.height, row.height);
        verify(row.height > 0);
        compare(row.pointerActivationExclusion, rowExclusion);
        const mapped = rowExclusion.mapToItem(row, 0, 0);
        compare(mapped.x, 200);
        compare(mapped.y, 0);
        compare(row.pointerInsideExclusion(Qt.point(row.width - 10, row.height / 2)), true);
        compare(row.pointerInsideExclusion(Qt.point(10, row.height / 2)), false);
        row.activateFromPointer(Qt.point(row.width - 10, row.height / 2));
        compare(rowTriggers, 0);
        row.activateFromPointer(Qt.point(10, row.height / 2));
        compare(rowTriggers, 1);
    }

    function test_slider_keyboard_and_accessibility_actions() {
        slider.forceActiveFocus();
        tryCompare(slider, "activeFocus", true);
        keyClick(Qt.Key_Right);
        compare(sliderMovedValue, 55);
        keyClick(Qt.Key_Home);
        compare(sliderMovedValue, 0);
        keyClick(Qt.Key_End);
        compare(sliderMovedValue, 100);

        sliderMovedValue = -1;
        slider.Accessible.increaseAction();
        compare(sliderMovedValue, 55);
        slider.Accessible.decreaseAction();
        compare(sliderMovedValue, 45);
    }

    function test_focus_scroll_follows_visible_bounds() {
        compare(FocusScroll.contentYForFocus(120, 20, 100, 100, 300, 8), 100);
        compare(FocusScroll.contentYForFocus(90, 20, 100, 100, 300, 8), 82);
        compare(FocusScroll.contentYForFocus(190, 20, 100, 100, 300, 8), 118);
        compare(FocusScroll.contentYForFocus(290, 20, 100, 100, 300, 8), 200);
        compare(FocusScroll.contentYForFocus(0, 20, 100, 100, 300, 8), 0);
        compare(FocusScroll.contentYForFocus(40, 20, 0, 200, 100, 8), 0);
    }

    function test_disabled_or_busy_controls_do_not_activate() {
        control.enabled = false;
        control.Accessible.pressAction();
        compare(controlTriggers, 0);

        action.busy = true;
        action.Accessible.pressAction();
        compare(actionTriggers, 0);

        row.activationBlocked = true;
        row.Accessible.pressAction();
        compare(rowTriggers, 0);
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
