import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Das Aufnahme-Menue -- Omarchys Capture-Menue, hier als nbshell-Overlay.
//
// Wie das Power-Menue: Liste mit Buchstaben davor, Enter bestaetigt. Nach der
// The selection closes immediately and waits briefly before capture so the
// overlay is no longer present in the resulting frame.
// verschwundene Menue mit im Screenshot.
PanelWindow {
    id: root

    property int selected: 0
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

    screen: Compositor.focusedScreen
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
        CaptureService.schedule(id);
        close();
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

                    PanelRow {
                        id: row

                        required property var modelData
                        required property int index

                        width: column.width
                        title: row.modelData.label
                        detail: row.modelData.detail || ""
                        value: row.modelData.key.toUpperCase()
                        selected: row.index === root.selected
                        interactive: true
                        accessibleDescription: [detail,
                            root.windowMode ? "Capture this window" : "Capture action",
                            "shortcut " + value].filter(part => part !== "").join("; ")
                        onHoveredChanged: if (hovered) root.selected = row.index
                        onTriggered: {
                            root.selected = row.index;
                            root.accept();
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
