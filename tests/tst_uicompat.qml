import QtQuick
import QtTest
import qs.Commons
import qs.Ui as Ui
import "../plugins/ytmusic" as YtMusic
import "../shell/Menu" as Menu

Item {
    id: host
    width: 800
    height: 300

    property int buttonClicks: 0
    property int actionClicks: 0
    property int nonTabButtonClicks: 0
    property int nonTabActionClicks: 0
    property int sliderMoves: 0
    property int sliderReleases: 0
    property int sliderRightClicks: 0
    property int playbackCommits: 0
    property real playbackCommittedValue: -1
    property int dashboardPrimaryTriggers: 0
    property int dashboardSecondaryTriggers: 0

    Ui.BorderSurface {
        id: surface
        width: 120
        height: 60
        padding: 7
        borderSpec: Border.flat(Color.accent, 2)
    }

    Ui.Button {
        id: button
        x: 140
        text: "Apply"
        iconText: "+"
        tooltipText: "Apply changes"
        focusable: true
        bordered: true
        onClicked: host.buttonClicks += 1
    }

    Ui.PanelActionButton {
        id: action
        x: 300
        iconText: "×"
        tooltipText: "Remove"
        focusable: true
        onClicked: host.actionClicks += 1
    }

    Ui.PanelSlider {
        id: slider
        x: 360
        width: implicitWidth
        height: implicitHeight
        value: 0.5
        minimum: 0
        maximum: 1
        step: 0.1
        tickCount: 5
        accessibleName: "Preview level"
        accessibleDescription: "Adjusts the preview level"
        onMoved: host.sliderMoves += 1
        onReleased: host.sliderReleases += 1
        onRightClicked: host.sliderRightClicks += 1
    }

    Ui.TextField {
        id: field
        y: 100
        text: "query"
        placeholderText: "Search"
        password: false
    }

    YtMusic.PlaybackSlider {
        id: playbackSlider
        y: 180
        width: 200
        minimum: 0
        maximum: 100
        step: 10
        sourceValue: 20
        accessibleName: "Seek"
        onCommitted: function(value) {
            host.playbackCommits += 1;
            host.playbackCommittedValue = value;
        }
    }

    Menu.DashboardAction {
        id: dashboardAction
        x: 220
        y: 200
        label: "Updates"
        detail: "2 available"
        rightLabel: "Install updates"
        run: function() { host.dashboardPrimaryTriggers += 1; }
        rightRun: function() { host.dashboardSecondaryTriggers += 1; }
    }

    Ui.Button {
        id: nonTabButton
        x: 240
        y: 120
        text: "Background action"
        onClicked: host.nonTabButtonClicks += 1
    }

    Ui.PanelActionButton {
        id: nonTabAction
        x: 400
        y: 120
        iconText: "×"
        tooltipText: "Clear"
        onClicked: host.nonTabActionClicks += 1
    }

    TestCase {
        name: "UiCompatibilityContracts"
        when: windowShown

        function dynamicMember(object, key) { return object[key]; }

        function cleanup() {
            host.buttonClicks = 0;
            host.actionClicks = 0;
            host.nonTabButtonClicks = 0;
            host.nonTabActionClicks = 0;
            host.sliderMoves = 0;
            host.sliderReleases = 0;
            host.sliderRightClicks = 0;
            host.playbackCommits = 0;
            host.playbackCommittedValue = -1;
            host.dashboardPrimaryTriggers = 0;
            host.dashboardSecondaryTriggers = 0;
            dashboardAction.enabled = true;
            playbackSlider.clearPreview();
            playbackSlider.sourceValue = 20;
            slider.minimum = 0;
            slider.maximum = 1;
            slider.step = 0.1;
            slider.integer = false;
            slider.value = 0.5;
            slider.enabled = true;
            button.accessibleName = "";
            button.accessibleDescription = "";
            field.accessibleName = "";
            field.accessibleDescription = "";
            field.password = false;
            nonTabAction.enabled = true;
        }

        function test_border_surface_public_api() {
            compare(surface.padding, 7);
            compare(surface.borderTop, 2);
            compare(surface.borderRight, 2);
            compare(surface.contentLeftInset, 9);
            // Overlay/gradient rendering is intentionally outside this contract
            // while the production Border adapter reserves but disables it.
            compare(surface.usesOverlayBorder, false);
        }

        function test_button_public_api_and_signal() {
            compare(button.text, "Apply");
            compare(button.iconText, "+");
            compare(button.tooltipText, "Apply changes");
            compare(button.focusable, true);
            compare(button.Accessible.name, "Apply");
            compare(button.Accessible.description, "Apply changes");
            compare(button.Accessible.role, Accessible.Button);
            button.forceActiveFocus();
            tryCompare(button, "activeFocus", true);
            keyClick(Qt.Key_Space);
            compare(host.buttonClicks, 1);
        }

        function test_explicit_button_accessibility_overrides() {
            button.accessibleName = "Apply settings";
            button.accessibleDescription = "Save the current configuration";
            compare(button.Accessible.name, "Apply settings");
            compare(button.Accessible.description, "Save the current configuration");
        }

        function test_panel_action_public_api_and_signal() {
            compare(action.iconText, "×");
            compare(action.tooltipText, "Remove");
            compare(action.focusable, true);
            compare(action.Accessible.name, "Remove");
            compare(action.Accessible.role, Accessible.Button);
            action.forceActiveFocus();
            tryCompare(action, "activeFocus", true);
            keyClick(Qt.Key_Return);
            compare(host.actionClicks, 1);
        }

        function test_non_tabbable_buttons_remain_at_accessible() {
            compare(nonTabButton.focusable, false);
            compare(nonTabButton.activeFocusOnTab, false);
            compare(nonTabButton.Accessible.focusable, true);
            nonTabButton.Accessible.pressAction();
            compare(host.nonTabButtonClicks, 1);

            compare(nonTabAction.focusable, false);
            compare(nonTabAction.activeFocusOnTab, false);
            compare(nonTabAction.Accessible.name, "Clear");
            nonTabAction.Accessible.pressAction();
            compare(host.nonTabActionClicks, 1);

            nonTabAction.enabled = false;
            nonTabAction.Accessible.pressAction();
            compare(host.nonTabActionClicks, 1);
        }

        function test_button_activation_guards() {
            nonTabButton.enabled = false;
            nonTabButton.Accessible.pressAction();
            compare(host.nonTabButtonClicks, 0);
            nonTabButton.enabled = true;

            const repeated = { "isAutoRepeat": true, "accepted": false };
            button.activateFromKey(repeated);
            compare(host.buttonClicks, 0);
            compare(repeated.accepted, true);
        }

        function test_slider_public_api_and_signals() {
            compare(slider.value, 0.5);
            compare(slider.minimum, 0);
            compare(slider.maximum, 1);
            compare(slider.step, 0.1);
            compare(slider.tickCount, 5);
            wait(20);
            mouseMove(slider, slider.width * 0.6, slider.height / 2);
            wait(20);
            mousePress(slider, slider.width * 0.6, slider.height / 2, Qt.LeftButton);
            wait(10);
            mouseRelease(slider, slider.width * 0.6, slider.height / 2, Qt.LeftButton);
            mouseClick(slider, slider.width / 2, slider.height / 2, Qt.RightButton);
            compare(host.sliderMoves, 1);
            compare(host.sliderReleases, 1);
            compare(host.sliderRightClicks, 1);
        }

        function test_slider_accessibility_actions() {
            compare(slider.Accessible.role, Accessible.Slider);
            compare(slider.Accessible.name, "Preview level");
            compare(slider.Accessible.description, "Adjusts the preview level");
            compare(slider.Accessible.focusable, true);
            compare(slider.activeFocusOnTab, false);
            compare(slider.minimumValue, 0);
            compare(slider.maximumValue, 1);
            compare(slider.stepSize, 0.1);

            slider.Accessible.increaseAction();
            compare(slider.liveValue, 0.6);
            compare(host.sliderMoves, 1);
            compare(host.sliderReleases, 1);

            slider.Accessible.decreaseAction();
            compare(slider.liveValue, 0.5);
            compare(host.sliderMoves, 2);
            compare(host.sliderReleases, 2);

            slider.maximum = 2;
            slider.step = 5;
            slider.integer = true;
            slider.Accessible.increaseAction();
            compare(slider.liveValue, 2);
            slider.Accessible.decreaseAction();
            compare(slider.liveValue, 0);

            slider.enabled = false;
            compare(slider.Accessible.focusable, false);
            slider.Accessible.increaseAction();
            compare(slider.liveValue, 0);
            compare(host.sliderMoves, 4);
            compare(host.sliderReleases, 4);
        }

        function test_playback_slider_accessibility_commits_once() {
            playbackSlider.Accessible.increaseAction();
            compare(host.playbackCommits, 1);
            compare(host.playbackCommittedValue, 30);
            compare(playbackSlider.pendingValue, 30);
        }

        function test_dashboard_action_accessibility_and_primary_activation() {
            compare(dashboardAction.Accessible.name, "Updates");
            compare(dashboardAction.Accessible.description, "2 available");
            compare(dashboardAction.Accessible.focusable, true);
            dashboardAction.Accessible.pressAction();
            compare(host.dashboardPrimaryTriggers, 1);
            compare(host.dashboardSecondaryTriggers, 0);

            dashboardAction.forceActiveFocus();
            tryCompare(dashboardAction, "activeFocus", true);
            keyClick(Qt.Key_Space);
            compare(host.dashboardPrimaryTriggers, 2);
        }

        function test_dashboard_action_secondary_pointer_and_disabled_guards() {
            const button = dashboardAction.secondaryButton;
            const secondaryPoint = button.mapToItem(
                dashboardAction, button.width / 2, button.height / 2);
            verify(dashboardAction.pointerInsideSecondary(secondaryPoint));

            dashboardAction.activateFromPointer(secondaryPoint, Qt.LeftButton);
            compare(host.dashboardPrimaryTriggers, 0);
            compare(host.dashboardSecondaryTriggers, 0);

            button.Accessible.pressAction();
            compare(host.dashboardSecondaryTriggers, 1);
            button.rightTriggered();
            compare(host.dashboardSecondaryTriggers, 2);

            dashboardAction.activateFromPointer(Qt.point(10, 10), Qt.LeftButton);
            compare(host.dashboardPrimaryTriggers, 1);
            dashboardAction.activateFromPointer(Qt.point(10, 10), Qt.RightButton);
            compare(host.dashboardSecondaryTriggers, 3);

            dashboardAction.enabled = false;
            dashboardAction.activateFromPointer(Qt.point(10, 10), Qt.LeftButton);
            dashboardAction.triggerSecondary();
            compare(host.dashboardPrimaryTriggers, 1);
            compare(host.dashboardSecondaryTriggers, 3);
        }

        function test_adapter_singleton_contracts() {
            compare(Style.space(10), 10);
            verify(Style.normalFillFor(Color.foreground, Color.accent).valid);
            verify(Style.hoverFillFor(Color.foreground, Color.accent).valid);
            verify(Style.selectedFillFor(Color.foreground, Color.accent).valid);
            verify(Style.pressedFillFor(Color.foreground, Color.accent).valid);
            compare(Style.normalBorderFor(Color.foreground, Color.accent), "#a0a0a0");
            compare(Style.hoverBorderFor(Color.foreground, Color.accent), "#80b8ff");
            compare(Style.focusBorderFor(Color.foreground, Color.accent), "#80b8ff");
            compare(Style.selectedBorderFor(Color.foreground, Color.accent), "transparent");
            compare(Style.stateBorderWidth("selected"), 0);
            compare(Style.stateBorderWidth("focus"), 1);
            verify(dynamicMember(Style.spacing, "panelPadding") > 0);
            verify(dynamicMember(Style.spacing, "searchableDropdownWidth") > dynamicMember(Style.spacing, "dropdownWidth"));
            verify(dynamicMember(Style.font, "display") > dynamicMember(Style.font, "heading"));
            compare(Style.controlBorder(false, false, Color.foreground, Color.accent), "#707070");
            compare(Style.controlBorder(true, true, Color.foreground, Color.accent), "#80b8ff");
            compare(dynamicMember(Color.popups, "background"), "#101010");
            compare(dynamicMember(Color.popups, "border"), "#80b8ff");
            compare(Color.urgent, "#ff6060");

            const normal = Border.controlSpec("normal", Color.foreground, Color.accent);
            const focus = Border.controlSpec("focus", Color.foreground, Color.accent);
            compare(Border.top(normal), 1);
            compare(Border.right(normal), 1);
            compare(Border.uniformWidth(focus), 1);
            compare(Border.controlHasWidth("selected"), false);
            compare(Border.canUseNative(normal), true);
            compare(Border.needsOverlay(normal), false);
        }

        function test_text_field_inherited_api() {
            compare(field.text, "query");
            compare(field.placeholderText, "Search");
            compare(field.password, false);
            verify(field.horizontalPadding > 0);
            verify(field.verticalPadding > 0);
        }

        function test_text_field_accessibility_api() {
            compare(field.Accessible.name, "Search");
            compare(field.Accessible.description, "");
            compare(field.Accessible.passwordEdit, false);
            field.accessibleName = "Mail search";
            field.accessibleDescription = "Accepts Gmail search operators";
            compare(field.Accessible.name, "Mail search");
            compare(field.Accessible.description, "Accepts Gmail search operators");
            field.password = true;
            compare(field.echoMode, TextInput.Password);
            compare(field.Accessible.passwordEdit, true);
        }
    }
}
