pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Anbindung an niri ueber dessen IPC-Socket ($NIRI_SOCKET).
//
// Der Socket ist nur zum ZUHOEREN da: `"EventStream"` einmal senden, danach
// kommen Zeilen. Beim Verbinden liefert er erst den vollstaendigen Zustand
// (WorkspacesChanged, WindowsChanged), danach nur noch Aenderungen -- man muss
// also nichts abfragen.
//
// Befehle gehen dagegen ueber `niri msg action`, NICHT ueber einen zweiten
// Socket. Grund: niri beantwortet pro Verbindung genau eine Anfrage und legt
// dann auf. Ein dauerhaft offener Befehls-Socket funktioniert damit genau
// einmal und schweigt danach -- lautlos, weil das Schreiben selbst gelingt.
// Die CLI liegt ohnehin bei, sie IST niri.
//
// Bewusst schlank: hier steht nur, was die Leiste anzeigt. Fenstergeometrie,
// Layouts und Ausgabenverwaltung fehlen absichtlich.
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""
    readonly property bool available: socketPath !== ""

    property var workspaces: []
    property var windows: []
    property int focusedWindowId: -1
    property string keyboardLayout: ""

    readonly property var focusedWindow: {
        for (var i = 0; i < windows.length; i++) {
            if (windows[i].id === focusedWindowId)
                return windows[i];
        }
        return null;
    }

    readonly property string focusedTitle: focusedWindow?.title ?? ""
    readonly property string focusedAppId: focusedWindow?.app_id ?? ""

    function workspacesForOutput(output) {
        return workspaces.filter(w => !output || w.output === output).sort((a, b) => a.idx - b.idx);
    }

    function focusWorkspace(idx) {
        action(["focus-workspace", String(idx)]);
    }

    function action(args) {
        Quickshell.execDetached(["niri", "msg", "action"].concat(args));
    }

    function handle(event) {
        const kind = Object.keys(event)[0];
        const data = event[kind];

        switch (kind) {
        case "WorkspacesChanged":
            workspaces = data.workspaces;
            break;
        case "WorkspaceActivated":
            // niri meldet nur die neue -- die alte muss man selbst loeschen.
            workspaces = workspaces.map(w => {
                if (w.output !== _outputOf(data.id))
                    return w;
                const active = w.id === data.id;
                return Object.assign({}, w, {
                    "is_active": active,
                    "is_focused": data.focused ? active : w.is_focused
                });
            });
            break;
        case "WorkspaceActiveWindowChanged":
            break;
        case "WindowsChanged":
            windows = data.windows;
            focusedWindowId = (windows.find(w => w.is_focused)?.id) ?? -1;
            break;
        case "WindowOpenedOrChanged":
            const rest = windows.filter(w => w.id !== data.window.id);
            rest.push(data.window);
            windows = rest;
            if (data.window.is_focused)
                focusedWindowId = data.window.id;
            break;
        case "WindowClosed":
            windows = windows.filter(w => w.id !== data.id);
            break;
        case "WindowFocusChanged":
            focusedWindowId = data.id ?? -1;
            // Wer in ein anderes Fenster klickt, will das Popout nicht mehr.
            if (Runtime.popoutCount > 0)
                Runtime.closeAll();
            break;
        case "KeyboardLayoutsChanged":
            keyboardLayout = data.keyboard_layouts.names[data.keyboard_layouts.current_idx] ?? "";
            break;
        case "KeyboardLayoutSwitched":
            keyboardLayout = _layoutNames[data.idx] ?? keyboardLayout;
            break;
        }

        if (kind === "KeyboardLayoutsChanged")
            _layoutNames = data.keyboard_layouts.names;
    }

    property var _layoutNames: []

    function _outputOf(workspaceId) {
        const w = workspaces.find(x => x.id === workspaceId);
        return w?.output ?? "";
    }

    Socket {
        id: eventSocket

        path: root.socketPath
        connected: root.available

        onConnectionStateChanged: {
            if (connected)
                write('"EventStream"\n');
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line);
                    // Die Antwort auf den Abonnementbefehl ist kein Ereignis.
                    if (event.Ok !== undefined || event.Err !== undefined)
                        return;
                    root.handle(event);
                } catch (e) {
                    console.warn("nbshell/niri: Zeile unlesbar:", e);
                }
            }
        }
    }

}
