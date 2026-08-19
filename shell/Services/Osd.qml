pragma Singleton

import QtQuick
import Quickshell
import qs.Common

// Die kurze Einblendung beim Regeln von Lautstaerke oder Helligkeit.
//
// Hier steht nur der Zustand -- gezeigt wird er in Osd/Osd.qml. So bleibt es
// bei einer Wahrheit, auch wenn mehrere Bildschirme sie anzeigen.
Singleton {
    id: root

    readonly property bool enabled: Config.value("osd", true)
    readonly property int timeout: Config.value("osdTimeout", 2000)

    property bool showing: false
    property string kind: ""

    readonly property int value: {
        switch (kind) {
        case "volume":
            return Audio.volume;
        case "mic":
            return Audio.micVolume;
        case "brightness":
            return Brightness.percent;
        }
        return 0;
    }

    readonly property bool muted: kind === "volume" ? Audio.muted : (kind === "mic" ? Audio.micMuted : false)

    readonly property string label: {
        switch (kind) {
        case "volume":
            return "VOLUME";
        case "mic":
            return "MICROPHONE";
        case "brightness":
            return "BRIGHTNESS";
        }
        return "";
    }

    readonly property color tint: {
        switch (kind) {
        case "brightness":
            return Theme.yellow;
        case "mic":
            return Theme.green;
        }
        return Theme.accent;
    }

    // Beim Start setzen sich die Werte erst -- ohne diese Sperre blitzte die
    // Einblendung bei jedem Neustart der Shell auf.
    property bool armed: false

    Timer {
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hideTimer
        interval: root.timeout
        onTriggered: root.showing = false
    }

    function show(which) {
        if (!enabled || !armed)
            return;
        // Wer den Regler vor sich hat, braucht daneben keine zweite Anzeige.
        if ((which === "volume" || which === "mic") && Runtime.audioPanelOpen)
            return;
        if (which === "brightness" && Runtime.controlOpen)
            return;
        kind = which;
        showing = true;
        hideTimer.restart();
    }

    Connections {
        target: Audio

        function onVolumeChanged() {
            root.show("volume");
        }

        function onMutedChanged() {
            root.show("volume");
        }

        function onMicMutedChanged() {
            root.show("mic");
        }
    }

    Connections {
        target: Brightness

        function onPercentChanged() {
            root.show("brightness");
        }
    }
}
