import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root
    property var toolState: ({"ambience": "", "bypass": "unknown", "presets": []})
    property bool loading: false
    readonly property string script: Qt.resolvedUrl("../scripts/audio-tools.py").toString().replace("file://", "")
    visible: Runtime.audioToolsOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:audio-tools"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function run(args) { if (!proc.running) { loading = true; proc.command = ["python3", script].concat(args); proc.running = true; } }
    onVisibleChanged: if (visible) { run(["status"]); keys.forceActiveFocus(); }
    Process {
        id: proc
        stdout: StdioCollector { onStreamFinished: { try { root.toolState = JSON.parse(text); } catch (e) {} root.loading = false; } }
        stderr: StdioCollector { onStreamFinished: if (String(text).trim()) console.warn("audio-tools:", String(text).trim()) }
    }

    Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bgDarker, .78) }
    MouseArea { anchors.fill: parent; onClicked: Runtime.audioToolsOpen = false }
    FocusScope {
        id: keys; anchors.fill: parent; focus: root.visible
        Keys.onEscapePressed: Runtime.audioToolsOpen = false
        Keys.onPressed: event => { if (event.key === Qt.Key_F5) root.run(["status"]); }
        Rectangle {
            anchors.centerIn: parent; width: Theme.cellW * 72; height: Theme.cellH * 30
            color: Theme.bg; radius: Theme.radius; border.width: Theme.borderWidth; border.color: Theme.accent
            MouseArea { anchors.fill: parent }
            Column {
                anchors.fill: parent; anchors.margins: Theme.cellW * 2; spacing: Theme.cellH * .6
                PanelHead { rowWidth: parent.width; icon: Icons.volumeHigh; title: "Focus & equalizer"; subtitle: "PipeWire · EasyEffects"; badge: root.loading ? "…" : "" }
                Rule { rowWidth: parent.width }
                Line { text: "FOCUS SOUNDS"; color: Theme.fgDim }
                Row {
                    spacing: Theme.cellW
                    Repeater {
                        model: [{id:"pink",label:"Pink"},{id:"brown",label:"Braun"},{id:"rain",label:"Regen"},{id:"white",label:"Weiss"}]
                        Rectangle {
                            required property var modelData
                            width: Theme.cellW * 12; height: Theme.cellH * 3; radius: Theme.radius
                            color: root.toolState.ambience === modelData.id ? Theme.selection : Theme.bgLight
                            border.width: Theme.borderWidth; border.color: root.toolState.ambience === modelData.id ? Theme.accent : Theme.muted
                            Line { anchors.centerIn: parent; text: modelData.label; color: Theme.fg }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.run(["start", modelData.id]) }
                        }
                    }
                    Rectangle {
                        width: Theme.cellW * 12; height: Theme.cellH * 3; radius: Theme.radius; color: Theme.bgLight
                        Line { anchors.centerIn: parent; text: "Stop"; color: Theme.red }
                        MouseArea { anchors.fill: parent; onClicked: root.run(["stop"]) }
                    }
                }
                Line { text: "Runs as a separate PipeWire stream and can be controlled in the audio popout."; color: Theme.muted }
                Rule { rowWidth: parent.width }
                Line { text: "EQUALIZER"; color: Theme.fgDim }
                Row {
                    spacing: Theme.cellW * 2
                    Rectangle {
                        width: Theme.cellW * 21; height: Theme.cellH * 3; radius: Theme.radius
                        color: root.toolState.bypass === "an" ? Theme.bgLight : Theme.selection
                        border.width: Theme.borderWidth; border.color: Theme.accent
                        Line { anchors.centerIn: parent; text: root.toolState.bypass === "an" ? "Effects off" : "Effects active"; color: Theme.fg }
                        MouseArea { anchors.fill: parent; onClicked: root.run(["bypass"]) }
                    }
                    Rectangle {
                        width: Theme.cellW * 24; height: Theme.cellH * 3; radius: Theme.radius; color: Theme.bgLight
                        Line { anchors.centerIn: parent; text: "Edit equalizer"; color: Theme.fg }
                        MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["easyeffects"]) }
                    }
                }
                Line { text: root.toolState.presets.length ? "PRESETS" : "No presets yet · save one in the editor, then press F5"; color: Theme.fgDim }
                Flow {
                    width: parent.width; spacing: Theme.cellW
                    Repeater {
                        model: root.toolState.presets
                        Rectangle {
                            required property string modelData
                            width: Math.max(Theme.cellW * 12, label.implicitWidth + Theme.cellW * 2); height: Theme.cellH * 2.5; radius: Theme.radius; color: Theme.bgLight
                            Line { id: label; anchors.centerIn: parent; text: modelData; color: Theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: root.run(["preset", modelData]) }
                        }
                    }
                }
                Item { width: 1; height: Theme.cellH }
                Line { text: "F5 refreshes · Esc closes"; color: Theme.muted }
            }
        }
    }
}
