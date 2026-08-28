//@ pragma UseQApplication
//@ pragma AppId dev.nerdi.nbshell.lock
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland

ShellRoot {
    id: shell
    readonly property bool previewMode: Quickshell.env("NBSHELL_LOCK_PREVIEW") === "1"
    readonly property string configPath: Quickshell.env("NBSHELL_LOCK_CONFIG")
    readonly property string readyPath: Quickshell.env("NBSHELL_LOCK_READY")
    property string username: Quickshell.env("USER")
    property string wallpaper: ""
    property color background: "#1a1b26"
    property color foreground: "#c0caf5"
    property color muted: "#565f89"
    property color accent: "#7aa2f7"
    property color danger: "#f7768e"
    property string fontFamily: "JetBrainsMono Nerd Font"
    property real dimOpacity: 0.48
    property string hourFormat: "24"
    property bool showSecondsRing: true
    property bool authenticating: false
    property string pendingSecret: ""
    property string statusMessage: previewMode ? "PREVIEW · AUTHENTICATION DISABLED" : "ENTER PASSWORD"
    property bool statusError: false
    property int resetSerial: 0

    function loadConfig() {
        let value = {};
        try { value = JSON.parse(configFile.text() || "{}"); }
        catch (error) { statusMessage = "INVALID LOCK CONFIGURATION"; statusError = true; return; }
        username = String(value.username || username); wallpaper = String(value.wallpaper || "");
        background = value.background || background; foreground = value.foreground || foreground;
        muted = value.muted || muted; accent = value.accent || accent; danger = value.red || danger;
        fontFamily = String(value.font || fontFamily).replace(/[\r\n]/g, " ");
        dimOpacity = Math.max(0, Math.min(.85, Number(value.dimOpacity) || .48));
        hourFormat = String(value.hourFormat) === "12" ? "12" : "24";
        showSecondsRing = value.showSecondsRing !== false;
    }
    function authenticate(secret) {
        if (previewMode || authenticating || typeof secret !== "string" || !secret.length) return;
        pendingSecret = secret; authenticating = true; statusError = false; statusMessage = "AUTHENTICATING";
        if (!pam.start()) {
            pendingSecret = "";
            authenticating = false;
            resetSerial += 1;
            statusMessage = "AUTHENTICATION SERVICE UNAVAILABLE";
            statusError = true;
        }
    }
    function reset() {
        pendingSecret = ""; resetSerial += 1;
        if (!authenticating) { statusMessage = "ENTER PASSWORD"; statusError = false; }
    }
    function unlock() {
        pendingSecret = "";
        sessionLock.locked = false;
        Qt.quit();
    }

    FileView { id: configFile; path: shell.configPath; blockLoading: true; printErrors: true }
    PamContext {
        id: pam
        config: "nbshell-lock"
        user: shell.username
        onPamMessage: {
            if (this.responseRequired) {
                const secret = shell.pendingSecret;
                shell.pendingSecret = "";
                this.respond(secret);
            } else if (this.message) {
                shell.statusMessage = String(this.message).toUpperCase();
            }
        }
        onCompleted: result => {
            shell.pendingSecret = "";
            shell.authenticating = false;
            shell.resetSerial += 1;
            if (result === PamResult.Success) shell.unlock();
            else { shell.statusMessage = "ACCESS DENIED"; shell.statusError = true; }
        }
    }
    Process { id: readyProcess; command: ["/usr/bin/touch", shell.readyPath] }
    WlSessionLock {
        id: sessionLock
        locked: !shell.previewMode
        onSecureStateChanged: if (secure && shell.readyPath) readyProcess.running = true
        WlSessionLockSurface {
            id: lockSurface
            color: shell.background
            readonly property bool primary: !Quickshell.screens.length || screen.name === Quickshell.screens[0].name
            LockView {
                anchors.fill: parent; primary: lockSurface.primary; previewMode: false
                username: shell.username; wallpaper: shell.wallpaper; background: shell.background
                foreground: shell.foreground; muted: shell.muted; accent: shell.accent; danger: shell.danger
                fontFamily: shell.fontFamily; dimOpacity: shell.dimOpacity; hourFormat: shell.hourFormat
                showSecondsRing: shell.showSecondsRing; authenticating: shell.authenticating
                statusMessage: shell.statusMessage; statusError: shell.statusError; resetSerial: shell.resetSerial
                onSubmitted: secret => shell.authenticate(secret); onResetRequested: shell.reset()
            }
        }
    }
    Variants {
        model: shell.previewMode ? Quickshell.screens : []
        PanelWindow {
            id: previewSurface
            required property var modelData
            readonly property bool primary: !Quickshell.screens.length || modelData.name === Quickshell.screens[0].name
            screen: modelData; anchors { left:true; right:true; top:true; bottom:true }
            exclusionMode: ExclusionMode.Ignore; color: "transparent"
            WlrLayershell.namespace: "nbshell:orbital-lock-preview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            LockView {
                anchors.fill: parent; primary: previewSurface.primary; previewMode: true
                username: shell.username; wallpaper: shell.wallpaper; background: shell.background
                foreground: shell.foreground; muted: shell.muted; accent: shell.accent; danger: shell.danger
                fontFamily: shell.fontFamily; dimOpacity: shell.dimOpacity; hourFormat: shell.hourFormat
                showSecondsRing: shell.showSecondsRing; authenticating: false
                statusMessage: shell.statusMessage; statusError: shell.statusError; resetSerial: shell.resetSerial
                onQuitPreview: Qt.quit()
            }
        }
    }
    Component.onCompleted: loadConfig()
}
