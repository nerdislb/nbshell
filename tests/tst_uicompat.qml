import QtQuick
import QtTest
import qs.Commons
import qs.Ui as Ui

Item {
    id: host
    width: 800
    height: 300

    property int buttonClicks: 0
    property int actionClicks: 0
    property int sliderMoves: 0
    property int sliderReleases: 0
    property int sliderRightClicks: 0

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

    TestCase {
        name: "UiCompatibilityContracts"
        when: windowShown

        function cleanup() {
            host.buttonClicks = 0;
            host.actionClicks = 0;
            host.sliderMoves = 0;
            host.sliderReleases = 0;
            host.sliderRightClicks = 0;
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
            button.forceActiveFocus();
            tryCompare(button, "activeFocus", true);
            keyClick(Qt.Key_Space);
            compare(host.buttonClicks, 1);
        }

        function test_panel_action_public_api_and_signal() {
            compare(action.iconText, "×");
            compare(action.tooltipText, "Remove");
            compare(action.focusable, true);
            action.forceActiveFocus();
            tryCompare(action, "activeFocus", true);
            keyClick(Qt.Key_Return);
            compare(host.actionClicks, 1);
        }

        function test_slider_public_api_and_signals() {
            compare(slider.value, 0.5);
            compare(slider.minimum, 0);
            compare(slider.maximum, 1);
            compare(slider.step, 0.1);
            compare(slider.tickCount, 5);
            verify(waitForRendering(slider));
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

        function test_adapter_singleton_contracts() {
            compare(Style.space(10), 10);
            verify(Style.normalFillFor(Color.foreground, Color.accent).valid);
            verify(Style.hoverFillFor(Color.foreground, Color.accent).valid);
            verify(Style.selectedFillFor(Color.foreground, Color.accent).valid);
            verify(Style.pressedFillFor(Color.foreground, Color.accent).valid);

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
    }
}
