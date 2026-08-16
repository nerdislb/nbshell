pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common

// Native Bongo Cat fuer nbshell. Die vier MIT-lizenzierten Frames und die
// privacy-minimierte L/R-Zuordnung stammen aus HANCOREs Omarchy-Plugin.
// Der Helfer gibt niemals Tasten oder Text aus, sondern ausschliesslich L/R.
Singleton {
    id: root

    readonly property string helper: Qt.resolvedUrl("../scripts/bongo-input").toString().replace("file://", "")
    readonly property string access: Qt.resolvedUrl("../scripts/bongo-input-access").toString().replace("file://", "")
    readonly property bool active: Config.value("bongoActive", true)
    readonly property int catWidth: Math.max(80, Math.min(480, Config.value("bongoWidth", 220)))
    readonly property int catHeight: Math.round(catWidth * 360 / 864)
    readonly property int rightMargin: Math.max(0, Config.value("bongoRight", 24))
    readonly property int bottomMargin: Math.max(0, Config.value("bongoBottom", 48))
    readonly property int pressDuration: Math.max(40, Math.min(400, Config.value("bongoPressDuration", 105)))

    property bool leftDown: false
    property bool rightDown: false
    property bool authorized: false
    property bool stopping: false
    property string inputState: "startet"
    property int keyboards: 0
    property string error: ""

    readonly property string frame: leftDown && rightDown
        ? "bongo-cat-both-down.png"
        : leftDown ? "bongo-cat-left-down.png"
        : rightDown ? "bongo-cat-right-down.png"
        : "bongo-cat-both-up.png"
    readonly property url frameSource: Qt.resolvedUrl("../assets/bongocat/" + frame)

    function setActive(value) { Config.set("bongoActive", !!value); }
    function toggle() { setActive(!active); }
    function setWidth(value) { Config.set("bongoWidth", Math.max(80, Math.min(480, value))); }
    function move(dx, dy) {
        Config.set("bongoRight", Math.max(0, rightMargin + dx));
        Config.set("bongoBottom", Math.max(0, bottomMargin + dy));
    }
    function resetPosition() {
        Config.set("bongoRight", 24);
        Config.set("bongoBottom", 48);
        Config.set("bongoWidth", 220);
    }
    function pressLeft() { leftDown = true; leftRelease.restart(); }
    function pressRight() { rightDown = true; rightRelease.restart(); }
    function test() { pressLeft(); pressRight(); }

    function statusText() {
        if (!active) return "ausgeschaltet";
        if (inputState === "ready") return keyboards + (keyboards === 1 ? " Tastatur aktiv" : " Tastaturen aktiv");
        if (inputState === "permission")
            return error !== "" ? error : "Eingabezugriff erforderlich";
        if (inputState === "authorizing") return "warte auf Freigabe …";
        if (inputState === "no-device") return "keine Tastatur gefunden";
        return error !== "" ? error : inputState;
    }

    function handle(line) {
        const value = String(line || "").trim();
        if (value === "L") { pressLeft(); return; }
        if (value === "R") { pressRight(); return; }
        if (value.indexOf("STATUS\t") !== 0) return;
        const fields = value.split("\t");
        inputState = fields[1] || "error";
        keyboards = Math.max(0, parseInt(fields[2] || "0", 10) || 0);
        if (authorized && inputState === "permission")
            authorized = false;
    }

    function restartInput() {
        restartTimer.stop();
        if (!active) {
            authorized = false;
            inputState = "ausgeschaltet";
            if (inputProc.running) { stopping = true; inputProc.running = false; }
            return;
        }
        if (inputProc.running) { stopping = true; inputProc.running = false; return; }
        restartTimer.restart();
    }

    function allowInput() {
        if (!active) setActive(true);
        error = "";
        authorized = true;
        inputState = "authorizing";
        restartInput();
    }

    function revokeInput() {
        authorized = false;
        restartInput();
    }

    onActiveChanged: restartInput()
    Component.onCompleted: restartInput()

    Timer { id: leftRelease; interval: root.pressDuration; onTriggered: root.leftDown = false }
    Timer { id: rightRelease; interval: root.pressDuration; onTriggered: root.rightDown = false }
    Timer {
        id: restartTimer
        interval: 150
        onTriggered: {
            inputProc.command = root.authorized
                ? [root.access, "watch", root.helper, "--watch"]
                : [root.helper, "--watch"];
            inputProc.running = true;
        }
    }

    Process {
        id: inputProc
        stdout: SplitParser { onRead: line => root.handle(line) }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const message = String(text || "").trim();
                if (message !== "") root.error = message.split("\n")[0];
            }
        }
        onExited: code => {
            if (root.stopping) {
                root.stopping = false;
                if (root.active) restartTimer.restart();
                return;
            }
            if (root.authorized) {
                root.authorized = false;
                root.inputState = "permission";
            } else if (root.active) {
                root.inputState = code === 0 ? "permission" : "error";
            }
        }
    }

    IpcHandler {
        target: "bongo"
        function toggle(): void { root.toggle(); }
        function enable(): void { root.setActive(true); }
        function disable(): void { root.setActive(false); }
        function test(): void { root.test(); }
        function allowInput(): void { root.allowInput(); }
        function revokeInput(): void { root.revokeInput(); }
        function resize(width: int): void { root.setWidth(width); }
        function status(): string { return root.statusText(); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.active && modelData === (Quickshell.screens[0] ?? null)
            color: "transparent"
            implicitWidth: root.catWidth
            implicitHeight: root.catHeight
            exclusionMode: ExclusionMode.Ignore
            anchors { right: true; bottom: true }
            margins { right: root.rightMargin; bottom: root.bottomMargin }
            mask: Region {}
            WlrLayershell.namespace: "nbshell:bongocat"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Image {
                anchors.fill: parent
                source: root.frameSource
                fillMode: Image.Stretch
                smooth: true
                mipmap: true
            }
        }
    }
}
