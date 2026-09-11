import QtQuick
import QtTest
import "../shell/Services/NetWifiRows.js" as WifiRows

TestCase {
    name: "NetWifiRows"
    function net(name, signal, connected, security) {
        return {name:name, signalStrength:signal, connected:!!connected, security:security || 0, known:false};
    }
    function test_reservedNames() {
        const names = ["constructor", "toString", "__proto__", "hasOwnProperty"];
        compare(WifiRows.rows(names.map(n => net(n, 1))).length, names.length);
    }
    function test_duplicatePreference() {
        const weak = net("same", .2), strong = net("same", .9);
        compare(WifiRows.rows([weak,strong])[0].signalStrength, .9);
        compare(WifiRows.rows([strong,weak])[0].signalStrength, .9);
        weak.connected = true;
        const rows = WifiRows.rows([strong,weak,net("other", 1)]);
        compare(rows[0].name, "same");
        verify(rows[0].connected);
    }
    function test_snapshotAndReplacement() {
        const old = net("same", .4, false, 1);
        const row = WifiRows.rows([old])[0];
        old.name = "gone";
        compare(row.name, "same");
        compare(WifiRows.resolve([],row), null);
        const replacement = net("same", .8, false, 1);
        compare(WifiRows.resolve([old,replacement],row), replacement);
        compare(WifiRows.resolve([net("same",1,false,2)],row), null);
        compare(WifiRows.rows([replacement,net("same",1,false,2)]).length,2);
    }
    function test_destroyedBackendObject() {
        const object = Qt.createQmlObject('import QtQuick; QtObject { property string name: "temporary"; property real signalStrength: 0.8; property bool connected: false; property bool known: false; property int security: 1 }', this);
        const row = WifiRows.rows([object])[0];
        object.destroy();
        wait(1);
        compare(row.name, "temporary");
        compare(row.signalStrength, .8);
        compare(WifiRows.resolve([], row), null);
    }
    function test_empty() {
        compare(WifiRows.rows([null,net("",1)]).length,0);
        compare(WifiRows.resolve([],null),null);
    }
}
