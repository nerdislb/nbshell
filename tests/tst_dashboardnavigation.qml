import QtQuick
import QtTest
import "../shell/Menu" as Menu

Item {
    width: 800
    height: 600
    property int primary: 0
    property int secondary: 0

    Flow {
        id: grid
        width: 660
        spacing: 10
        Repeater {
            id: tiles
            model: 14
            Menu.DashboardAction {
                required property int index
                width: 150
                height: 60
                label: "Tool " + index
                directionalNavigation: true
                run: () => primary++
                rightRun: index === 4 ? () => secondary++ : null
                rightLabel: "Secondary"
            }
        }
    }

    TestCase {
        name: "DashboardSpatialNavigation"
        when: windowShown

        function tile(i) { return tiles.itemAt(i); }
        function checkFocus(i) {
            verify(tile(i).activeFocus);
            verify(tile(i).Accessible.focused);
            verify(tile(i).visualFocus);
        }
        function init() {
            grid.width = 660;
            for (let i = 0; i < 14; ++i)
                tile(i).enabled = true;
            grid.forceLayout();
            primary = 0;
            secondary = 0;
            tile(0).forceActiveFocus();
        }
        function test_spatialEdgesAndPartialRow() {
            keyClick(Qt.Key_Left); checkFocus(0);
            keyClick(Qt.Key_Up); checkFocus(0);
            keyClick(Qt.Key_Right); checkFocus(1);
            keyClick(Qt.Key_Down); checkFocus(5);
            keyClick(Qt.Key_Left); checkFocus(4);
            keyClick(Qt.Key_Up); checkFocus(0);
            tile(11).forceActiveFocus();
            keyClick(Qt.Key_Down); checkFocus(13);
            keyClick(Qt.Key_Right); checkFocus(13);
            keyClick(Qt.Key_Down); checkFocus(13);
        }
        function test_reflow() {
            grid.width = 500;
            grid.forceLayout();
            keyClick(Qt.Key_Down); checkFocus(3);
            keyClick(Qt.Key_Right); checkFocus(4);
            keyClick(Qt.Key_Down); checkFocus(7);
            keyClick(Qt.Key_Up); checkFocus(4);
        }
        function test_disabledAndActivation() {
            tile(1).enabled = false;
            keyClick(Qt.Key_Right); checkFocus(2);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(primary, 2);
            compare(secondary, 0);
        }
        function test_tabSecondaryAndArrows() {
            tile(4).forceActiveFocus();
            keyClick(Qt.Key_Tab);
            verify(tile(4).secondaryButton.activeFocus);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(secondary, 2);
            compare(primary, 0);
            keyClick(Qt.Key_Tab, Qt.ShiftModifier); checkFocus(4);
            keyClick(Qt.Key_Tab);
            keyClick(Qt.Key_Right); checkFocus(5);
            keyClick(Qt.Key_Tab, Qt.ShiftModifier);
            verify(tile(4).secondaryButton.activeFocus);
        }
    }
}
