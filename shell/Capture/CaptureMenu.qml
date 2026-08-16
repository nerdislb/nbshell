import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Das Aufnahme-Menue -- Omarchys Capture-Menue, hier als nbshell-Overlay.
//
// Wie das Power-Menue: Liste mit Buchstaben davor, Enter bestaetigt. Nach der
// Wahl schliesst es SOFORT und wartet kurz, bevor es ausloest -- niri friert
// das Bild ein, sobald die Aktion ankommt, und ohne Pause haengt das halb
// verschwundene Menue mit im Screenshot.
PanelWindow {
    id: root

    property int selected: 0
    property string pending: ""

    readonly property var actions: [
        { "id": "screen", "label": "Bildschirm", "key": "b" },
        { "id": "window", "label": "Fenster", "key": "f" },
        { "id": "region", "label": "Bereich", "key": "a" },
        { "id": "ocr", "label": "Text erkennen", "key": "t" },
        { "id": "qr", "label": "QR-Code erkennen", "key": "q" },
        { "id": "record", "label": CaptureService.recording ? "Aufnahme beenden" : "Aufnahme starten", "key": "v" },
        { "id": "edit", "label": "Letztes bearbeiten", "key": "e" },
        { "id": "open", "label": "Ordner oeffnen", "key": "o" }
    ]

    visible: Runtime.captureOpen

    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:capture"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.captureOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() {
        Runtime.captureOpen = false;
    }

    function choose(id) {
        root.pending = id;
        close();
        delay.restart();
    }

    function accept() {
        const action = root.actions[selected];
        if (action)
            choose(action.id);
    }

    // 250 ms reichen, damit das Overlay wirklich weg ist.
    Timer {
        id: delay
        interval: 250
        onTriggered: {
            switch (root.pending) {
            case "screen":
            case "window":
            case "region":
                CaptureService.shoot(root.pending);
                break;
            case "ocr":
                CaptureService.ocr();
                break;
            case "qr":
                CaptureService.qr();
                break;
            case "record":
                CaptureService.toggleRecording();
                break;
            case "edit":
                CaptureService.editLast();
                break;
            case "open":
                CaptureService.openDir();
                break;
            }
            root.pending = "";
        }
    }

    onVisibleChanged: {
        if (visible) {
            selected = 0;
            keys.forceActiveFocus();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: root.accept()
        Keys.onEnterPressed: root.accept()
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min(root.actions.length - 1, root.selected + 1)
        Keys.onPressed: event => {
            const letter = event.text.toLowerCase();
            for (var i = 0; i < root.actions.length; i++) {
                if (root.actions[i].key === letter) {
                    root.selected = i;
                    root.accept();
                    event.accepted = true;
                    return;
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Theme.cellW * 38
            height: column.implicitHeight + Theme.cellH * 2

            color: Theme.bg
            radius: Theme.radius
            border.width: Theme.borderWidth
            border.color: CaptureService.recording ? Theme.red : Theme.accent

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width - Theme.cellW * 2
                spacing: Theme.cellH * 0.2

                Line {
                    text: CaptureService.recording ? "AUFNAHME LAEUFT" : "AUFNEHMEN"
                    color: CaptureService.recording ? Theme.red : Theme.fgDim
                    bottomPadding: Theme.cellH * 0.4
                }

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        height: Theme.cellH * 1.6
                        radius: Theme.radius
                        color: row.index === root.selected ? Theme.selection : "transparent"

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: (row.index === root.selected ? "▸ " : "  ") + "[" + row.modelData.key + "]  " + row.modelData.label
                            color: row.index === root.selected ? Theme.on(Theme.selection) : Theme.fg
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = row.index
                            onClicked: root.accept()
                        }
                    }
                }

                Line {
                    text: "Esc schliesst"
                    color: Theme.muted
                    topPadding: Theme.cellH * 0.4
                }
            }
        }
    }
}
