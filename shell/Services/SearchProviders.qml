pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Extra launcher providers. Window, clipboard, and calculator queries are
// evaluated from state nbshell already owns. File search is explicit (`@`)
// and debounced, so no indexer or background process exists while idle.
Singleton {
    id: root

    property string pendingFileQuery: ""
    property string activeFileQuery: ""
    property var files: []
    property string fileError: ""
    property bool fileBusy: fileSearch.running

    function rankWindows(query) {
        if (!query) return [];
        return Compositor.windows.map(window => {
            const title = String(window.title || window.app_id || "Window");
            const app = String(window.app_id || "");
            return {
                entry: {
                    kind: "window",
                    name: title,
                    comment: app,
                    category: "Window",
                    windowId: String(window.id || "")
                },
                points: Math.max(Apps.score(title, query), Apps.score(app, query) * 0.7) + 4
            };
        }).filter(row => row.entry.windowId && row.points > 4)
          .sort((a, b) => b.points - a.points);
    }

    function rankClipboard(query) {
        if (!query) return [];
        return Clipboard.entries.map((text, index) => ({
            entry: {
                kind: "clipboard",
                name: Clipboard.preview(text, 72),
                comment: "Copy this history entry",
                category: "Clipboard",
                value: text
            },
            points: Apps.score(text, query) + Math.max(0, 5 - index * 0.1)
        })).filter(row => row.points > 0).sort((a, b) => b.points - a.points);
    }

    function calculator(query) {
        const expression = String(query || "").trim();
        if (!expression || !/[0-9]/.test(expression) || !/[+\-*/×÷%()]/.test(expression))
            return [];
        try {
            const value = CalculatorEngine.evaluate(expression);
            return [{
                entry: {
                    kind: "calculator",
                    name: expression + " = " + value,
                    comment: "Copy result",
                    category: "Calculator",
                    value: value
                },
                points: 200
            }];
        } catch (error) {
            return [];
        }
    }

    function requestFiles(query) {
        pendingFileQuery = String(query || "").trim();
        if (pendingFileQuery.length < 2) {
            files = [];
            activeFileQuery = "";
            fileDelay.stop();
            return;
        }
        fileDelay.restart();
    }

    function fileRows(query) {
        return String(query || "").trim() === activeFileQuery ? files : [];
    }

    function activate(entry) {
        if (!entry) return false;
        if (entry.kind === "window") {
            Compositor.focusWindow(entry.windowId);
            return true;
        }
        if (entry.kind === "clipboard" || entry.kind === "calculator") {
            Clipboard.copy(String(entry.value || ""));
            return true;
        }
        if (entry.kind === "file") {
            Quickshell.execDetached(["xdg-open", entry.path]);
            return true;
        }
        return false;
    }

    Timer {
        id: fileDelay
        interval: 180
        repeat: false
        onTriggered: {
            root.activeFileQuery = root.pendingFileQuery;
            root.files = [];
            root.fileError = "";
            fileSearch.command = ["/usr/bin/fd", "--type", "f", "--hidden", "--exclude", ".git", "--exclude", ".cache", "--exclude", "node_modules", "--exclude", "target", "--exclude", ".local/share/Steam", "--max-results", "40", "--", root.activeFileQuery, Quickshell.env("HOME")];
            fileSearch.running = true;
        }
    }

    Process {
        id: fileSearch
        stdout: StdioCollector {
            onStreamFinished: {
                const query = root.activeFileQuery;
                root.files = text.split("\n").filter(path => path !== "").map(path => ({
                    entry: {
                        kind: "file",
                        name: path.split("/").pop(),
                        comment: path.replace(Quickshell.env("HOME"), "~"),
                        category: "File",
                        path: path
                    },
                    points: Apps.score(path.split("/").pop(), query)
                })).sort((a, b) => b.points - a.points);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: root.fileError = String(text).trim()
        }
        onExited: code => {
            if (Number(code) !== 0 && !root.fileError)
                root.fileError = "fd exited with status " + code;
        }
    }
}
