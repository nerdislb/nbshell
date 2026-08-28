import QtQuick
import QtTest
import "../shell/lock/ClockMath.js" as ClockMath

TestCase {
    name: "NbshellLockClockMath"
    function test_angles() {
        const date = new Date(2026, 7, 26, 15, 30, 15, 500);
        compare(Math.round(ClockMath.secondAngle(date) * 10) / 10, 93);
        compare(Math.round(ClockMath.minuteAngle(date) * 100) / 100, 181.55);
        compare(ClockMath.visibleEdgeRotation(30), 120);
        compare(ClockMath.normalizeAngle(-370), 350);
        compare(ClockMath.angularDistance(-10, 370), 20);
    }
    function test_hour_text() {
        compare(ClockMath.hourText(new Date(2026, 7, 26, 0, 45), "24"), "00");
        compare(ClockMath.hourText(new Date(2026, 7, 26, 0, 45), "12"), "12");
        compare(ClockMath.hourText(new Date(2026, 7, 26, 15, 45), "12"), "03");
    }
}
