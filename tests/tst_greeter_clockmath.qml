import QtQuick
import QtTest
import "../greeter/qml/ClockMath.js" as ClockMath

TestCase {
    name: "NbshellOrbitalClock"

    function test_angles() {
        const date = new Date(2026, 7, 26, 15, 30, 15, 500);
        compare(Math.round(ClockMath.secondAngle(date) * 10) / 10, -93);
        compare(Math.round(ClockMath.minuteAngle(date) * 100) / 100, -181.55);
        compare(ClockMath.normalizeAngle(-90), 270);
        compare(ClockMath.angularDistance(350, 10), 20);
    }

    function test_hour_text() {
        compare(ClockMath.hourText(new Date(2026, 7, 26, 0, 0, 0), "24"), "00");
        compare(ClockMath.hourText(new Date(2026, 7, 26, 0, 0, 0), "12"), "12");
        compare(ClockMath.hourText(new Date(2026, 7, 26, 15, 0, 0), "12"), "03");
    }

    function test_visible_edge_alignment() {
        const date = new Date(2026, 7, 26, 3, 3, 3, 0);
        const minuteMarker = 3 * 6 + ClockMath.visibleEdgeRotation(ClockMath.minuteAngle(date));
        const secondMarker = 3 * 6 + ClockMath.visibleEdgeRotation(ClockMath.secondAngle(date));
        compare(Math.round(minuteMarker * 10) / 10, 89.7);
        compare(secondMarker, 90);
    }
}
