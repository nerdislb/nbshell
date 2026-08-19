import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets

// Headset-Akku -- ueber headsetcontrol (USB-HID++, Logitech & co.).
//
// Ein Plugin, kein eingebauter Baustein: es liegt unter
// ~/.config/nbshell/plugins/headset und ueberlebt jedes `install.sh`.
//
// Zeigt sich nur, wenn headsetcontrol wirklich einen Akkustand liefert --
// aus oder Dongle nicht da heisst schlicht: Zelle weg, kein "—" in der Leiste.
Cell {
    id: root

    readonly property int interval: 30000

    property var data: ({})
    property bool loading: false

    readonly property bool ready: data.ok === true
    readonly property int level: ready ? (data.level ?? 0) : 0
    readonly property bool charging: ready && data.charging === true

    shown: root.ready
    label: "HEADSET"
    icon: charging ? Icons.batteryCharging : String.fromCodePoint(0xF02CB)
    text: root.level + "%"
    color: root.level <= 20 && !root.charging ? Theme.red : (root.charging ? Theme.green : Theme.text)
    interactive: true
    slotChars: 4

    onClicked: root.refresh()

    Component.onCompleted: root.refresh()

    function refresh() {
        if (root.loading)
            return;
        root.loading = true;
        proc.command = ["bash", Qt.resolvedUrl("headset.sh").toString().replace("file://", "")];
        proc.running = true;
    }

    Process {
        id: proc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(text);
                } catch (e) {
                    console.warn("nbshell/headset: Antwort unlesbar —", e);
                    root.data = ({
                        "ok": false
                    });
                }
                root.loading = false;
            }
        }
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    popout: Component {
        Column {
            id: panel

            property var closePopout: null

            readonly property real rowWidth: Theme.cellW * 30

            spacing: Theme.cellH * 0.25

            Text {
                text: root.ready ? String(root.data.geraet).toUpperCase() : "HEADSET"
                color: Theme.readable(Theme.accent, Theme.bg)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                renderType: Text.QtRendering
            }

            Text {
                width: panel.rowWidth
                text: root.ready ? (root.level + " %" + (root.charging ? "   charging" : "")) : "no device"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
                renderType: Text.QtRendering
            }

            LevelBar {
                visible: root.ready
                cells: 30
                value: root.level
                interactive: false
                fillColor: root.level <= 20 && !root.charging ? Theme.red : (root.charging ? Theme.green : Theme.accent)
            }
        }
    }
}
