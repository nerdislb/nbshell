import QtQuick
import QtTest
import "../shell/Bar/Widgets" as BarWidgets

Item {
    width: 160; height: 160
    BarWidgets.DuoGlyph {
        id: glyph
        width: 128; height: 128
        foreground: "black"
        urgent: "red"
    }
    TestCase {
    name: "DuoGlyph"
    when: windowShown
    function shot() {
        glyph.requestPaint();
        waitForRendering(glyph);
        wait(100);
        return grabImage(glyph);
    }
    function test_live_states_repaint() {
        glyph.batteryPresent=true; glyph.battery=0.8;
        glyph.wifiConnected=true; glyph.wifiEnabled=true; glyph.signalStrength=1;
        glyph.wired=false; glyph.bluetoothEnabled=false; glyph.charging=false; glyph.lowBattery=false;
        const normal=shot();
        glyph.battery=0.15; glyph.lowBattery=true;
        const low=shot(); verify(!normal.equals(low), "low battery changes arc");
        glyph.lowBattery=false; glyph.charging=true;
        const charging=shot(); verify(!low.equals(charging), "charging mark appears");
        glyph.bluetoothEnabled=true;
        const bt=shot(); verify(!charging.equals(bt), "radio changes four dots");
        glyph.signalStrength=0.2;
        const weak=shot(); verify(!bt.equals(weak), "signal changes inner arcs");
        glyph.wifiConnected=false; glyph.wifiEnabled=false;
        const off=shot(); verify(!weak.equals(off), "disabled radio is crossed out");
        glyph.wired=true;
        const wired=shot(); verify(!off.equals(wired), "wired symbol replaces Wi-Fi");
        glyph.charging=false; glyph.batteryPresent=false;
        const desktop=shot(); verify(!wired.equals(desktop), "no battery hides filled arc");
        glyph.foreground="blue";
        verify(!desktop.equals(shot()), "light theme redraws");
    }
}
}
