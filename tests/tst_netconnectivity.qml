import QtQuick
import QtTest
import "../shell/Services/NetConnectivity.js" as Connectivity

TestCase {
    name: "NetConnectivity"
    readonly property var states: ({Unknown: 0, None: 1, Portal: 2, Limited: 3, Full: 4})

    function test_state_data() {
        return [
            {tag: "offline overrides cached full", connected: false, enabled: true, value: 4, expected: "offline"},
            {tag: "offline overrides portal", connected: false, enabled: true, value: 2, expected: "offline"},
            {tag: "disabled ignores cached full", connected: true, enabled: false, value: 4, expected: "unknown"},
            {tag: "disabled ignores cached portal", connected: true, enabled: false, value: 2, expected: "unknown"},
            {tag: "full", connected: true, enabled: true, value: 4, expected: "full"},
            {tag: "portal", connected: true, enabled: true, value: 2, expected: "portal"},
            {tag: "limited", connected: true, enabled: true, value: 3, expected: "limited"},
            {tag: "connected without internet", connected: true, enabled: true, value: 1, expected: "none"},
            {tag: "unknown", connected: true, enabled: true, value: 0, expected: "unknown"},
            {tag: "unrecognized", connected: true, enabled: true, value: 99, expected: "unknown"}
        ];
    }
    function test_state(data) {
        compare(Connectivity.state(data.connected, data.enabled, data.value, states), data.expected);
    }
    function test_labels() {
        compare(Connectivity.label("unknown", false), "Internet check unavailable or disabled");
        compare(Connectivity.label("offline", false), "Not connected");
        compare(Connectivity.label("portal", true), "Network sign-in required");
        verify(Connectivity.label("limited", true) !== Connectivity.label("full", true));
    }
}
