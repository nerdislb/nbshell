pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Stable shell-facing boundary for the Umbriel compositor.
Singleton {
    id: root

    readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID")))
    readonly property string waylandDisplay: String(Quickshell.env("WAYLAND_DISPLAY") || "wayland-0")
    readonly property string umbrielSocket: String(Quickshell.env("UMBRIEL_SOCKET") || (runtimeDir + "/umbriel-" + waylandDisplay + ".sock"))
    readonly property int contractVersion: 1
    readonly property string backend: "umbriel"
    readonly property string socketPath: umbrielSocket
    readonly property bool available: ipc.connected
    readonly property string status: available ? "ready" : "offline"
    readonly property bool isUmbriel: true
    property string lastError: ""
    property bool _connectRequested: true

    property var workspaces: []
    property var windows: []
    property var focusedWindowId: ""
    property string keyboardLayout: ""
    property var _layoutNames: []

    property string focusedOutput: ""
    readonly property var focusedScreen: Quickshell.screens.find(screen => screen.name === focusedOutput)
        ?? Quickshell.screens[0] ?? null

    readonly property var focusedWindow: windows.find(w => String(w.id) === String(focusedWindowId)) ?? null
    readonly property string focusedTitle: focusedWindow?.title ?? ""
    readonly property string focusedAppId: focusedWindow?.app_id ?? ""

    function workspaceOutput(rows, workspace) {
        const value = String(workspace ?? "");
        if (value === "")
            return "";
        const match = (rows ?? []).find(w => String(w.id) === value
            || String(w.name) === value
            || (String(w.output) + ":" + String(w.name)) === value);
        return match?.output ?? "";
    }

    function workspacesForOutput(output) {
        return workspaces.filter(w => !output || !w.output || w.output === output).sort((a, b) => a.idx - b.idx);
    }

    function focusWorkspace(value) {
        Quickshell.execDetached(["umbriel", "msg", "workspace-switch:" + String(value)]);
    }

    function focusWindow(id) {
        Quickshell.execDetached(["umbriel", "msg", "window-focus:" + String(id)]);
    }

    function logout() {
        Quickshell.execDetached(["umbriel", "msg", "session-quit:skip-confirmation"]);
    }

    function reloadConfig() {
        Quickshell.execDetached(["umbriel", "msg", "config-reload"]);
    }

    function turnOutputsOff() {
        Quickshell.execDetached(["umbriel", "msg", "dpms-off"]);
    }

    function clearState() {
        workspaces = [];
        windows = [];
        focusedWindowId = "";
        focusedOutput = "";
        keyboardLayout = "";
        _layoutNames = [];
    }

    function scheduleReconnect() {
        _connectRequested = false;
        reconnectTimer.restart();
    }

    function normalizeWindows(rows) {
        const normalized = (rows ?? []).map(w => Object.assign({}, w, {
            "is_focused": Boolean(w.focused),
            "is_active": Boolean(w.active),
            "is_floating": Boolean(w.floating)
        }));
        windows = normalized;
        focusedWindowId = String(normalized.find(w => w.is_focused)?.id ?? "");
        const focusedWorkspace = normalized.find(w => w.is_focused)?.workspace ?? "";
        const focusedWorkspaceOutput = workspaceOutput(workspaces, focusedWorkspace);
        if (focusedWorkspaceOutput !== "")
            focusedOutput = focusedWorkspaceOutput;

    }

    function normalizeWorkspaces(rows) {
        workspaces = (rows ?? []).map(w => Object.assign({}, w, {
            "idx": Number(w.index ?? 0),
            "is_active": Boolean(w.active),
            "is_focused": Boolean(w.focused),
            "is_urgent": Boolean(w.urgent)
        }));
        focusedOutput = String(workspaces.find(w => w.is_focused)?.output ?? focusedOutput);
    }

    function handleEvent(event) {
        if (event.event === "workspaces") {
            normalizeWorkspaces(event.data);
        } else if (event.event === "windows") {
            const oldFocus = focusedWindowId;
            normalizeWindows(event.data);
            if (oldFocus !== "" && oldFocus !== focusedWindowId && Runtime.popoutCount > 0 && !focusGuard.running)
                Runtime.closeAll();
        } else if (event.event === "keyboard_layout") {
            _layoutNames = event.data?.names ?? [];
            keyboardLayout = _layoutNames[event.data?.current_index ?? 0] ?? "";
        }
    }


    Socket {
        id: ipc
        path: root.socketPath
        connected: root._connectRequested
        onConnectionStateChanged: {
            if (connected) {
                root.lastError = "";
                write(JSON.stringify({"cmd": "subscribe", "events": ["workspaces", "windows", "keyboard_layout"]}) + "\n");
            } else {
                root.lastError = "ipc-unavailable";
                root.clearState();
                root.scheduleReconnect();
            }
        }
        onError: root.scheduleReconnect()
        parser: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line);
                    if (event.Err !== undefined || event.err !== undefined) {
                        root.lastError = "ipc-error";
                        return;
                    }
                    if (event.Ok !== undefined || event.ok !== undefined)
                        return;
                    root.handleEvent(event);
                } catch (error) {
                    root.lastError = "invalid-event";
                    console.warn("nbshell/compositor: unreadable IPC event:", error);
                }
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        repeat: false
        onTriggered: root._connectRequested = true
    }

    Timer { id: focusGuard; interval: 600 }
    Connections {
        target: Runtime
        function onBarHoverChanged() { focusGuard.restart(); }
        function onPopoutHoverChanged() { focusGuard.restart(); }
        function onPopoutCountChanged() { if (Runtime.popoutCount > 0) focusGuard.restart(); }
    }
}
