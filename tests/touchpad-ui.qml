import QtQuick
import QtQuick.Window as Windows
import QtTest
import Quickshell
import qs.Common
import "Touchpad" as Input

ShellRoot {
    Windows.Window {
        id: window
        visible: true
        width: 900
        height: 1000
        color: Theme.panelSurface
        Input.TouchpadPanel { id: panel; anchors.fill: parent; autoLoad: false }
        TestCase {
            name: "NativeTouchpad"
            windowShown: window.visible
            when: window.visible
            function check(value) { if (!value) { console.error("CHECK FAILED", new Error().stack); fail("Check failed"); } }
            function equal(a,b) { if (a !== b) { console.error("COMPARE FAILED",a,b,new Error().stack); fail("Comparison failed"); } }
            function initTestCase() {
                Theme.sourceEnabled = false;
                panel.state = {devices:[{name:"DELL09C3:00 0488:120A Touchpad"}], warnings:[], scope:"All touchpads", canRestore:false};
                panel.saved = {profile:"system",curve:{precision:.1875,start:.8,end:2.8,fast:1}};
                panel.draft = JSON.parse(JSON.stringify(panel.saved));
                panel.loaded = true;
                panel.message = "Test draft — no configuration writes";
            }
            function button(item, label) {
                if ((item.text === label || item.accessibleName === label) && item.activate !== undefined) return item;
                for (let i=0; i<item.children.length; i++) { const found=button(item.children[i],label); if(found) return found; }
                return null;
            }
            function test_a_preset_and_keyboard() {
                const preset=button(panel,"MAC-INSPIRED"); check(preset !== null);
                mouseClick(preset); wait(50);
                equal(panel.draft.profile,"mac"); equal(panel.draft.curve.precision,.1875); equal(panel.draft.curve.fast,1);
                check(panel.dirty);
                const handle=findChild(panel,"curveHandle0");check(handle !== null);
                handle.forceActiveFocus();keyClick(Qt.Key_Up);
                equal(panel.draft.profile,"custom");check(panel.draft.curve.precision > .1875);
                check(!button(panel,"RESTORE PREVIOUS").enabled);
            }
            function test_b_drag_curve() {
                const handle=findChild(panel,"curveHandle3");
                const old=panel.draft.curve.fast;
                mouseDrag(handle,handle.width/2,handle.height/2,0,30,Qt.LeftButton);
                check(panel.draft.curve.fast < old);
                check(panel.draft.curve.fast >= panel.draft.curve.precision);
            }
            function test_c_dark_light_small_reduced() {
                const palettes=[{mode:"light",background:"#dad4b9",foreground:"#1c2d28",accent:"#087e8b"},{mode:"dark",background:"#1a1b26",foreground:"#c0caf5",dark_foreground:"#9aa5ce",accent:"#7aa2f7"}];
                for(let i=0;i<palettes.length;i++) {
                    Theme.c=palettes[i];wait(50);
                    grabImage(window.contentItem).save(String(Qt.resolvedUrl("capture-"+i+".png")).replace("file://",""));
                }
                Config.data = Object.assign({}, Config.data, {motionProfile:"reduced"});check(Theme.reducedMotion);
                window.width=420;window.height=620;wait(50);
                check(button(panel,"APPLY & TRY").y >= 0);
                grabImage(window.contentItem).save(String(Qt.resolvedUrl("capture-small.png")).replace("file://",""));
            }
            function test_d_keyboard_scroll() {
                const scroller=findChild(panel,"touchpadScroll");
                const handle=findChild(panel,"curveHandle0");handle.forceActiveFocus();
                for(let i=0;i<25;i++) keyClick(Qt.Key_Tab);
                check(scroller.contentItem.contentY > 0);
            }
            function test_e_empty_error() {
                panel.state={devices:[],warnings:["Device-specific overrides remain active."],scope:"All touchpads"};
                panel.message="Simulated configuration conflict. Refresh before applying.";panel.failed=true;
                wait(50);
                grabImage(window.contentItem).save(String(Qt.resolvedUrl("capture-error.png")).replace("file://",""));
            }
            function cleanupTestCase() { console.log("TOUCHPAD_UI_RESULTS", qtest_results.passCount, qtest_results.failCount, qtest_results.skipCount); console.log(qtest_results.failCount === 0 ? "TOUCHPAD_UI_PASS" : "TOUCHPAD_UI_FAIL"); Qt.quit(); }
        }
    }
}
