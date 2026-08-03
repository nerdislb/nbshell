import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// Aufnahme-Zelle: waehrend einer Aufnahme rot mit Laufzeit, sonst ein stilles
// Kuerzel. Klick oeffnet das Menue, Rechtsklick startet und stoppt direkt.
Cell {
    id: root

    property int seconds: 0

    interactive: true
    color: CaptureService.recording ? Theme.red : Theme.textDim
    label: CaptureService.recording ? "REC" : "CAP"
    icon: CaptureService.recording ? Icons.record : Icons.camera
    text: CaptureService.recording ? (Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")) : ""

    onClicked: Runtime.captureOpen = true
    onRightClicked: CaptureService.toggleRecording()

    Timer {
        interval: 1000
        repeat: true
        running: CaptureService.recording
        onTriggered: root.seconds += 1
    }

    Connections {
        target: CaptureService

        function onRecordingChanged() {
            root.seconds = 0;
        }
    }
}
