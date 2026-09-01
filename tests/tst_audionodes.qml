import QtQuick
import QtTest
import "../shell/Services/AudioNodes.js" as AudioNodes

TestCase {
    name: "AudioNodes"

    function sink(name, options) {
        var values = options || {};
        return {
            "name": name,
            "audio": values.audio === undefined ? ({}) : values.audio,
            "isSink": values.isSink === undefined ? true : values.isSink,
            "isStream": values.isStream === true
        };
    }

    function test_filters_non_outputs() {
        var output = sink("speaker");
        compare(AudioNodes.uniqueSinks([
            output,
            sink("stream", {"isStream": true}),
            sink("source", {"isSink": false}),
            sink("no-audio", {"audio": null})
        ], output), [output]);
    }

    function test_deduplicates_stale_nodes_by_pipewire_name() {
        var stale = sink("alsa_output.pci.test.analog-stereo");
        var current = sink("alsa_output.pci.test.analog-stereo");
        var headphones = sink("bluez_output.test");
        compare(AudioNodes.uniqueSinks([stale, current, headphones], current), [current, headphones]);
    }

    function test_keeps_first_duplicate_without_a_preferred_match() {
        var first = sink("speaker");
        var duplicate = sink("speaker");
        compare(AudioNodes.uniqueSinks([first, duplicate], null), [first]);
    }

    function test_anonymous_nodes_remain_distinct() {
        var first = sink("");
        var second = sink("");
        compare(AudioNodes.uniqueSinks([first, second], first), [first, second]);
    }
}
