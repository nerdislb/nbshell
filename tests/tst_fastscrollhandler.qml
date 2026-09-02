import QtQuick
import QtTest
import "../integrations/omawhatsapp" as WhatsApp

TestCase {
    name: "FastScrollHandler"

    Flickable {
        id: viewport
        width: 320
        height: 100
        contentWidth: width
        contentHeight: 1000
    }

    WhatsApp.FastScrollHandler {
        id: handler
        flickable: viewport
        speedMultiplier: 4
        mouseWheelStep: 72
    }

    function init() {
        viewport.contentY = 0
    }

    function test_mouse_wheel_uses_fast_configured_step() {
        compare(handler.scrollDistance(0, -120), -288)
        compare(handler.scrollByDeltas(0, -120), 288)
        compare(viewport.contentY, 288)
    }

    function test_pixel_delta_is_accelerated_and_bounded() {
        compare(handler.scrollByDeltas(-50, 0), 200)
        compare(handler.scrollByDeltas(-1000, 0), 900)
        compare(handler.scrollByDeltas(1000, 0), 0)
    }
}