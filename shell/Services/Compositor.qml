pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Stable shell-facing compositor boundary. UI modules use this singleton and
// never need to know whether Niri or Umbriel owns the Wayland session.
Singleton {
    id: root

    readonly property string forcedBackend: String(Quickshell.env("NBSHELL_COMPOSITOR") ?? "").toLowerCase()
    readonly property string desktop: String(Quickshell.env("XDG_CURRENT_DESKTOP") ?? "").toLowerCase()
    readonly property string umbrielSocket: String(Quickshell.env("UMBRIEL_SOCKET") ?? "")
    readonly property string niriSocket: String(Quickshell.env("NIRI_SOCKET") ?? "")
    readonly property string workspaceHelper: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/nbshell/bin/umbriel-workspaces"
    readonly property string backend: forcedBackend || (umbrielSocket !== "" || desktop.indexOf("umbriel") >= 0 ? "umbriel" : "niri")
    readonly property string socketPath: backend === "umbriel" ? umbrielSocket : niriSocket
    readonly property bool available: socketPath !== ""
    readonly property bool isNiri: backend === "niri"
    readonly property bool isUmbriel: backend === "umbriel"

    property var workspaces: []
    property var windows: []
    property var focusedWindowId: ""
    property string keyboardLayout: ""
    property var _layoutNames: []
    property bool fullWorkspaceModel: false

    readonly property var focusedWindow: windows.find(w => String(w.id) === String(focusedWindowId)) ?? null
    readonly property string focusedTitle: focusedWindow?.title ?? ""
    readonly property string focusedAppId: focusedWindow?.app_id ?? ""

    function workspacesForOutput(output) {
        return workspaces.filter(w => !output || !w.output || w.output === output).sort((a, b) => a.idx - b.idx);
    }

    function focusWorkspace(value) {
        if (isUmbriel) {
            Quickshell.execDetached(["umbriel", "msg", "workspace-switch:" + String(value)]);
            return;
        }
        action(["focus-workspace", String(value)]);
    }

    function focusWindow(id) {
        if (isUmbriel) {
            Quickshell.execDetached(["umbriel", "msg", "window-focus:" + String(id)]);
            return;
        }
        action(["focus-window", "--id", String(id)]);
    }

    function logout() {
        if (isUmbriel)
            Quickshell.execDetached(["umbriel", "msg", "session-quit:skip-confirmation"]);
        else
            action(["quit", "--skip-confirmation"]);
    }

    // Compatibility action surface for the remaining Niri-native operations.
    // New cross-compositor callers should use the typed functions above.
    function action(args) {
        if (isNiri)
            Quickshell.execDetached(["niri", "msg", "action"].concat(args));
    }

    function normalizeUmbrielWindows(rows) {
        const normalized = (rows ?? []).map(w => Object.assign({}, w, {
            "is_focused": Boolean(w.focused),
            "is_active": Boolean(w.active),
            "is_floating": Boolean(w.floating)
        }));
        windows = normalized;
        focusedWindowId = String(normalized.find(w => w.is_focused)?.id ?? "");

        // Umbriel's current IPC exposes the workspace id on each window but
        // no standalone workspace event yet. This gives the bar a useful
        // initial model; a protocol helper will later add empty workspaces.
        const ids = [];
        for (const window of normalized) {
            const name = String(window.workspace || "");
            if (name && ids.indexOf(name) < 0)
                ids.push(name);
        }
        ids.sort((a, b) => {
            const an = Number(a), bn = Number(b);
            return Number.isFinite(an) && Number.isFinite(bn) ? an - bn : a.localeCompare(b);
        });
        if (fullWorkspaceModel)
            return;
        workspaces = ids.map((name, index) => ({
            "id": name,
            "idx": Number.isFinite(Number(name)) ? Number(name) : index + 1,
            "name": name,
            "output": "",
            "is_active": normalized.some(w => String(w.workspace) === name && w.is_focused),
            "is_focused": normalized.some(w => String(w.workspace) === name && w.is_focused),
            "is_urgent": normalized.some(w => String(w.workspace) === name && w.urgent)
        }));
    }

    function handleNiri(event) {
        const kind = Object.keys(event)[0];
        const data = event[kind];
        switch (kind) {
        case "WorkspacesChanged": workspaces = data.workspaces; break;
        case "WorkspaceActivated":
            const output = outputOf(data.id);
            workspaces = workspaces.map(w => {
                if (w.output !== output) return w;
                const active = w.id === data.id;
                return Object.assign({}, w, {
                    "is_active": active,
                    "is_focused": data.focused ? active : w.is_focused
                });
            });
            break;
        case "WindowsChanged":
            windows = data.windows;
            focusedWindowId = String(windows.find(w => w.is_focused)?.id ?? "");
            break;
        case "WindowOpenedOrChanged":
            windows = windows.filter(w => w.id !== data.window.id).concat([data.window]);
            if (data.window.is_focused) focusedWindowId = String(data.window.id);
            break;
        case "WindowClosed": windows = windows.filter(w => w.id !== data.id); break;
        case "WindowFocusChanged":
            focusedWindowId = String(data.id ?? "");
            if (Runtime.popoutCount > 0 && !focusGuard.running) Runtime.closeAll();
            break;
        case "KeyboardLayoutsChanged":
            _layoutNames = data.keyboard_layouts.names;
            keyboardLayout = _layoutNames[data.keyboard_layouts.current_idx] ?? "";
            break;
        case "KeyboardLayoutSwitched": keyboardLayout = _layoutNames[data.idx] ?? keyboardLayout; break;
        }
    }

    function handleUmbriel(event) {
        if (event.event === "workspaces") {
            fullWorkspaceModel = true;
            workspaces = event.data ?? [];
        } else if (event.event === "windows") {
            const oldFocus = focusedWindowId;
            normalizeUmbrielWindows(event.data);
            if (oldFocus !== "" && oldFocus !== focusedWindowId && Runtime.popoutCount > 0 && !focusGuard.running)
                Runtime.closeAll();
        } else if (event.event === "keyboard_layout") {
            _layoutNames = event.data?.names ?? [];
            keyboardLayout = _layoutNames[event.data?.current_index ?? 0] ?? "";
        }
    }

    Process {
        id: workspaceReader
        running: root.isUmbriel && root.available
        command: [root.workspaceHelper]
        onExited: code => root.fullWorkspaceModel = false
        stdout: SplitParser {
            onRead: line => {
                try { root.handleUmbriel(JSON.parse(line)); }
                catch (error) { console.warn("nbshell/compositor: unreadable workspace event:", error); }
            }
        }
    }

    function outputOf(workspaceId) {
        return workspaces.find(w => w.id === workspaceId)?.output ?? "";
    }

    Socket {
        path: root.socketPath
        connected: root.available
        onConnectionStateChanged: {
            if (!connected) return;
            if (root.isUmbriel)
                write(JSON.stringify({"cmd": "subscribe", "events": ["windows", "keyboard_layout"]}) + "\n");
            else
                write('"EventStream"\n');
        }
        parser: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line);
                    if (event.Ok !== undefined || event.Err !== undefined || event.ok !== undefined || event.err !== undefined)
                        return;
                    if (root.isUmbriel) root.handleUmbriel(event); else root.handleNiri(event);
                } catch (error) {
                    console.warn("nbshell/compositor: unreadable IPC event:", error);
                }
            }
        }
    }

    Timer { id: focusGuard; interval: 600 }
    Connections {
        target: Runtime
        function onBarHoverChanged() { focusGuard.restart(); }
        function onPopoutHoverChanged() { focusGuard.restart(); }
        function onPopoutCountChanged() { if (Runtime.popoutCount > 0) focusGuard.restart(); }
    }
}
