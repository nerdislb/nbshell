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
    property bool windowMode: false

    readonly property var actions: [
        { "id": "screen", "label": "Screen", "key": "b" },
        { "id": "window", "label": "Window", "key": "f" },
        { "id": "region", "label": "Region", "key": "a" },
        { "id": "ocr", "label": "Recognize text", "key": "t" },
        { "id": "qr", "label": "Scan QR code", "key": "q" },
        { "id": "dictate", "label": "Toggle dictation", "key": "d" },
        { "id": "record", "label": CaptureService.recording ? "Stop recording" : "Start recording", "key": "v" },
        { "id": "trim", "label": "Trim latest recording", "key": "c" },
        { "id": "stream", "label": "Open streaming studio", "key": "s" },
        { "id": "edit", "label": "Edit latest", "key": "e" },
        { "id": "open", "label": "Open folder", "key": "o" }
    ]
    readonly property var windowActions: Compositor.windows
        .filter(window => window.title || window.app_id)
        .sort((a, b) => String(a.title || a.app_id).localeCompare(String(b.title || b.app_id)))
        .map(window => ({
            "id": "window-" + window.id,
            "windowId": window.id,
            "label": window.title || window.app_id || "Window",
            "detail": window.app_id || "",
            "key": ""
        }))
    readonly property var shownActions: windowMode ? windowActions : actions

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
        windowMode = false;
        Runtime.captureWindowSelect = false;
        Runtime.captureOpen = false;
    }

    function choose(id) {
        root.pending = id;
        close();
        delay.restart();
    }

    function accept() {
        const action = root.shownActions[selected];
        if (!action)
            return;
        if (root.windowMode) {
            CaptureService.shootWindow(action.windowId);
            root.close();
        } else if (action.id === "window") {
            root.windowMode = true;
            root.selected = 0;
        } else {
            choose(action.id);
        }
    }

    // 250 ms reichen, damit das Overlay wirklich weg ist.
    Timer {
        id: delay
        interval: 250
        onTriggered: {
            switch (root.pending) {
            case "screen":
            case "region":
                CaptureService.shoot(root.pending);
                break;
            case "ocr":
                CaptureService.ocr();
                break;
            case "qr":
                CaptureService.qr();
                break;
            case "dictate":
                CaptureService.dictate();
                break;
            case "record":
                CaptureService.toggleRecording();
                break;
            case "stream":
                CaptureService.openStreamingStudio();
                break;
            case "trim":
                CaptureService.trimLastRecording();
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
            windowMode = Runtime.captureWindowSelect;
            Runtime.captureWindowSelect = false;
            selected = 0;
            keys.forceActiveFocus();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    FocusScope {
        id: keys

        anchors.fill: parent
        focus: root.visible

        Keys.onEscapePressed: {
            if (root.windowMode) {
                root.windowMode = false;
                root.selected = 0;
            } else {
                root.close();
            }
        }
        Keys.onReturnPressed: root.accept()
        Keys.onEnterPressed: root.accept()
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min(root.shownActions.length - 1, root.selected + 1)
        Keys.onPressed: event => {
            if (root.windowMode)
                return;
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

        PanelSurface {
            anchors.centerIn: parent
            width: Theme.cellW * 38
            height: column.implicitHeight + Theme.cellH * 2

            accentBorder: true

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: column

                anchors.centerIn: parent
                width: parent.width - Theme.cellW * 2
                spacing: Theme.cellH * 0.2

                SectionHeader {
                    width: column.width
                    text: root.windowMode ? "Select window" : (CaptureService.recording ? "Recording" : "Capture")
                    detail: root.windowMode ? root.shownActions.length + " windows" : "Choose an action"
                }

                Repeater {
                    model: root.shownActions

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        height: Theme.rowHeight
                        radius: Theme.radius
                        color: row.index === root.selected ? Theme.selectedSurface(Theme.accent) : Theme.panelSurfaceRaised
                        border.width: Theme.borderWidth
                        border.color: row.index === root.selected ? Theme.focusBorder : Theme.panelBorder

                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.borderWidth * 2
                            height: parent.height * 0.55
                            radius: width
                            color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.accent
                            visible: row.index === root.selected
                        }

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.cellW * 3
                            text: row.index === root.selected ? "▸ " + row.modelData.key.toUpperCase() : row.modelData.key.toUpperCase()
                            color: Theme.accent
                            font.bold: true
                        }

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.cellW * 3.5
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.cellW / 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label + (row.modelData.detail ? "  ·  " + row.modelData.detail : "")
                            color: row.index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg
                            font.pixelSize: Theme.fontBody
                            elide: Text.ElideRight
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
                    text: root.windowMode ? "↑/↓ select  ·  Enter or click capture  ·  Esc back" : "Esc closes"
                    color: Theme.muted
                    topPadding: Theme.cellH * 0.4
                }
            }
        }
    }
}
