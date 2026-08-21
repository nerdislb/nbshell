import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// User-facing plugin manager and curated nbshell store. Third-party QML runs
// inside the shell with the user's privileges, so discovery and execution are
// deliberately separate: install first, review, then enable.
PanelWindow {
    id: root

    property string tab: "installed"
    property string query: ""
    property int selected: 0
    property var catalog: []
    property string catalogError: ""
    property string statusText: ""
    property bool statusError: false
    property string pendingAction: ""
    property var pendingItem: null
    property string pendingDetail: ""
    property bool busy: false
    property var previewItem: null

    readonly property var installed: Plugins.plugins.map(item => {
        const listed = root.catalog.find(entry => entry.id === item.id) ?? ({});
        return Object.assign({}, listed, item, {
            license: item.license || listed.license || "",
            repository: item.repository || listed.repository || "",
            dependencies: Object.keys(item.dependencies ?? {}).length ? item.dependencies : (listed.dependencies ?? ({})),
            managed: item.managed || listed.source === "bundled"
        });
    }).filter(item => root.matches(item))
    readonly property var store: catalog.map(item => {
        const local = Plugins.entry(item.id);
        return Object.assign({}, item, local ?? ({}), {
            installed: !!local,
            local: local,
            managed: (local?.managed ?? false) || item.source === "bundled",
            gitManaged: local?.gitManaged ?? false,
            license: local?.license || item.license || "",
            repository: local?.repository || item.repository || "",
            dependencies: Object.keys(local?.dependencies ?? {}).length ? local.dependencies : (item.dependencies ?? ({}))
        });
    }).filter(item => root.matches(item))
    readonly property var list: tab === "store" ? store : installed
    readonly property var plugin: list[selected] ?? null

    visible: Runtime.pluginDeveloperOpen
    screen: Quickshell.screens[0] ?? null
    color: "transparent"

    WlrLayershell.namespace: "nbshell:plugin-manager"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() { Runtime.pluginDeveloperOpen = false; }
    function matches(item) {
        const needle = query.trim().toLowerCase();
        if (needle === "") return true;
        return [item?.name, item?.id, item?.description, item?.author, item?.category]
            .some(value => String(value || "").toLowerCase().indexOf(needle) >= 0);
    }
    function isEnabled(item) {
        const id = item?.id ?? "";
        return id !== "" && Plugins.enabledIds.indexOf(id) >= 0;
    }
    function localFor(item) { return item; }
    function selectTab(value) {
        tab = value;
        selected = 0;
        statusText = "";
        Qt.callLater(search.forceActiveFocus);
    }
    function toggleEnabled(item) {
        const local = localFor(item);
        if (!local?.id) return;
        const next = !isEnabled(local);
        Plugins.setEnabled(local.id, next);
        statusError = false;
        statusText = local.name + (next ? " enabled" : " disabled");
    }
    function ask(action, item, detail) {
        pendingAction = action;
        pendingItem = item;
        pendingDetail = detail || "";
    }
    function cancelPending() {
        pendingAction = "";
        pendingItem = null;
        pendingDetail = "";
    }
    function targetName(item) {
        const local = localFor(item);
        const parts = String(local?.dir || local?.id || "").split("/");
        return parts[parts.length - 1];
    }
    function confirmPending() {
        if (!pendingItem || pendingAction === "") return;
        const action = pendingAction;
        const item = pendingItem;
        cancelPending();
        if (action === "install")
            runAction(action, ["bash", Plugins.script, "add", String(item.repository)]);
        else if (action === "update")
            runAction(action, ["bash", Plugins.script, "update", targetName(item)]);
        else if (action === "remove")
            runAction(action, ["bash", Plugins.script, "remove", targetName(item)]);
    }
    function runAction(action, command) {
        if (busy) return;
        busy = true;
        statusError = false;
        statusText = action.charAt(0).toUpperCase() + action.slice(1) + " in progress…";
        actionProc.command = command;
        actionProc.running = true;
    }
    function previewUpdate(item) {
        if (busy || !item) return;
        busy = true;
        previewItem = item;
        statusError = false;
        statusText = "Checking the remote revision…";
        previewProc.command = ["bash", Plugins.script, "diff", targetName(item)];
        previewProc.running = true;
    }
    function repositoryUrl(item) {
        const value = String(localFor(item)?.repository || item?.repository || "");
        if (value.startsWith("https://")) return value;
        const ssh = value.match(/^git@github\.com:(.+?)(?:\.git)?$/);
        return ssh ? "https://github.com/" + ssh[1] : "";
    }
    function dependencyText(item) {
        const deps = localFor(item)?.dependencies ?? item?.dependencies ?? ({});
        const commands = deps.commands ?? [];
        return commands.length ? commands.join(" · ") : "None";
    }
    function actionLabel(item) {
        if (!item) return "";
        if (tab === "store" && !item.installed) return "INSTALL";
        return isEnabled(localFor(item)) ? "DISABLE" : "ENABLE";
    }
    function primaryAction(item) {
        if (!item) return;
        if (tab === "store" && !item.installed) {
            if (String(item.repository || "").startsWith("https://"))
                ask("install", item, "The plugin will be cloned but remain disabled until you review and enable it.");
            return;
        }
        toggleEnabled(item);
    }
    function stateText(item, kind) {
        const local = localFor(item);
        if (!local || !item?.installed && tab === "store") return "available";
        if (kind === "bar-widget") {
            const placed = ["collapsedWidgets", "leftWidgets", "centerWidgets", "rightWidgets"]
                .some(key => Config.value(key, []).indexOf(local.id) >= 0);
            return placed ? "in bar" : "not in bar";
        }
        if (!isEnabled(local)) return "disabled";
        const state = Plugins.loadState(local.id, kind);
        return state.state;
    }

    onListChanged: selected = Math.max(0, Math.min(selected, list.length - 1))
    onVisibleChanged: {
        if (visible) {
            tab = Runtime.pluginManagerTab;
            selected = 0;
            Plugins.refresh();
            Qt.callLater(search.forceActiveFocus);
        } else {
            cancelPending();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    FileView {
        path: Qt.resolvedUrl("../Catalog/plugins.json")
        printErrors: false
        onLoaded: {
            try {
                const document = JSON.parse(text() || "{}");
                root.catalog = Array.isArray(document.plugins) ? document.plugins : [];
                root.catalogError = "";
            } catch (error) {
                root.catalog = [];
                root.catalogError = "The bundled catalog is invalid";
            }
        }
        onLoadFailed: root.catalogError = "The bundled catalog could not be loaded"
    }

    Process {
        id: actionProc
        stdout: StdioCollector { id: actionOut }
        stderr: StdioCollector { id: actionErr }
        onExited: code => {
            root.busy = false;
            const output = String(actionOut.text || actionErr.text || "").trim().split("\n").slice(-1)[0];
            root.statusError = code !== 0;
            root.statusText = output || (code === 0 ? "Plugin action completed" : "Plugin action failed");
            Plugins.refresh();
        }
    }

    Process {
        id: previewProc
        stdout: StdioCollector { id: previewOut }
        stderr: StdioCollector { id: previewErr }
        onExited: code => {
            root.busy = false;
            const output = String(code === 0 ? previewOut.text : previewErr.text).trim();
            if (code !== 0 || output === "Already up to date.") {
                root.statusError = code !== 0;
                root.statusText = output || "Could not inspect the update";
                root.previewItem = null;
                return;
            }
            const clipped = output.length > 1400 ? output.slice(0, 1400) + "\n…" : output;
            const item = root.previewItem;
            root.previewItem = null;
            root.ask("update", item, clipped);
        }
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: {
            if (root.pendingAction !== "") root.cancelPending();
            else if (root.query !== "") root.query = "";
            else root.close();
        }
        Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
        Keys.onDownPressed: root.selected = Math.min(root.list.length - 1, root.selected + 1)
        Keys.onReturnPressed: root.primaryAction(root.plugin)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_1) { root.selectTab("installed"); event.accepted = true; }
            if (event.key === Qt.Key_2) { root.selectTab("store"); event.accepted = true; }
            if (event.key === Qt.Key_F5) { Plugins.refresh(); event.accepted = true; }
        }

        OverlaySurface {
            id: box
            preferredWidth: Theme.cellW * 104
            preferredHeight: Theme.cellH * 39
            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spaceLg
                spacing: Theme.spaceSm

                PanelHead {
                    rowWidth: box.width - Theme.spaceLg * 2
                    icon: Icons.cp(0xF12E)
                    title: "Plugins"
                    subtitle: "Installed modules and the curated nbshell store"
                    badge: String(root.list.length)
                }

                Row {
                    width: parent.width
                    height: Theme.controlHeight
                    spacing: Theme.spaceSm

                    ControlButton { text: "INSTALLED"; selected: root.tab === "installed"; onTriggered: root.selectTab("installed") }
                    ControlButton { text: "STORE"; selected: root.tab === "store"; onTriggered: root.selectTab("store") }

                    Rectangle {
                        width: parent.width - Theme.cellW * 25
                        height: Theme.controlHeight
                        radius: Theme.radius
                        color: Theme.alpha(Theme.fg, 0.06)
                        border.width: search.activeFocus ? Theme.borderWidth : 0
                        border.color: Theme.focusBorder

                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceMd
                            anchors.rightMargin: Theme.spaceMd
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.on(Theme.accent)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBody
                            text: root.query
                            onTextEdited: root.query = text
                            Keys.onPressed: event => {
                                if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_1) {
                                    root.selectTab("installed");
                                    event.accepted = true;
                                } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_2) {
                                    root.selectTab("store");
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_F5) {
                                    Plugins.refresh();
                                    event.accepted = true;
                                }
                            }
                        }

                        Line {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spaceMd
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === "" && !search.activeFocus
                            text: "Search plugins…"
                            color: Theme.muted
                        }
                    }
                }

                Rule { rowWidth: parent.width }

                Row {
                    width: parent.width
                    height: Theme.cellH * 28
                    spacing: Theme.spaceLg

                    Flickable {
                        id: pluginScroll
                        width: Theme.cellW * 38
                        height: parent.height
                        contentWidth: width
                        contentHeight: pluginRows.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: pluginRows
                            width: pluginScroll.width
                            spacing: Theme.spaceXs

                            Line {
                                visible: root.list.length === 0
                                width: parent.width
                                text: root.catalogError !== "" ? root.catalogError
                                    : (root.tab === "store" ? "No store entries match" : "No installed plugins match")
                                color: root.catalogError !== "" ? Theme.red : Theme.muted
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: root.list
                                Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: pluginRows.width
                                    height: Theme.cellH * 3.2
                                    radius: Theme.radius
                                    color: index === root.selected ? Theme.selectedSurface(Theme.accent)
                                        : Theme.alpha(Theme.fg, rowHover.hovered ? 0.08 : 0.035)

                                    Rectangle {
                                        width: Math.max(3, Theme.borderWidth * 2)
                                        height: parent.height - Theme.spaceMd
                                        x: Theme.spaceSm
                                        y: Theme.spaceSm / 2
                                        radius: width / 2
                                        color: root.isEnabled(root.localFor(modelData)) ? Theme.green : Theme.muted
                                        opacity: root.tab === "store" && !modelData.installed ? 0.25 : 1
                                    }

                                    Column {
                                        x: Theme.spaceLg
                                        y: Theme.spaceSm
                                        width: parent.width - Theme.spaceXl
                                        spacing: Theme.spaceXs
                                        Line { width: parent.width; text: modelData.name; color: index === root.selected ? Theme.selectedForeground(Theme.accent) : Theme.fg; font.bold: true; elide: Text.ElideRight }
                                        Line { width: parent.width; text: modelData.id; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideMiddle }
                                        Line { width: parent.width; text: modelData.description || "No description"; color: Theme.fgDim; font.pixelSize: Theme.fontCaption; elide: Text.ElideRight }
                                    }

                                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.selected = index }
                                    TapHandler { onTapped: root.selected = index }
                                }
                            }
                        }
                    }

                    Rectangle { width: Theme.borderWidth; height: parent.height; color: Theme.muted }

                    Column {
                        width: parent.width - Theme.cellW * 40 - Theme.spaceLg
                        spacing: Theme.spaceSm

                        Line { width: parent.width; text: root.plugin?.name ?? "Select a plugin"; color: Theme.fg; font.pixelSize: Theme.fontTitle; font.bold: true; elide: Text.ElideRight }
                        Line { width: parent.width; visible: !!root.plugin; text: root.plugin?.description ?? ""; color: Theme.fgDim; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
                        Rule { rowWidth: parent.width }
                        Line { width: parent.width; visible: !!root.plugin; text: "ID          " + (root.plugin?.id ?? ""); color: Theme.fgDim; elide: Text.ElideMiddle }
                        Line { width: parent.width; visible: !!root.plugin; text: "AUTHOR      " + (root.plugin?.author || "Unknown"); color: Theme.fgDim; elide: Text.ElideRight }
                        Line { width: parent.width; visible: !!root.plugin; text: "LICENSE     " + (root.plugin?.license || "Not declared"); color: root.plugin?.license ? Theme.fgDim : Theme.yellow; elide: Text.ElideRight }
                        Line { width: parent.width; visible: !!root.plugin; text: "SOURCE      " + (root.plugin?.managed ? "Bundled with nbshell" : (root.plugin?.gitManaged ? "Git checkout" : "Local folder")); color: Theme.fgDim }
                        Line { width: parent.width; visible: !!root.plugin; text: "REQUIRES    " + root.dependencyText(root.plugin); color: Theme.fgDim; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                        Line { width: parent.width; visible: !!root.plugin; text: "KINDS       " + ((root.plugin?.kinds ?? []).join(" · ") || "—"); color: Theme.fgDim; elide: Text.ElideRight }

                        Row {
                            visible: !!root.plugin
                            spacing: Theme.spaceSm
                            ControlButton { text: root.actionLabel(root.plugin); enabled: !root.busy; selected: root.isEnabled(root.localFor(root.plugin)); onTriggered: root.primaryAction(root.plugin) }
                            ControlButton { text: "SOURCE"; enabled: root.repositoryUrl(root.plugin) !== ""; onTriggered: Quickshell.execDetached(["xdg-open", root.repositoryUrl(root.plugin)]) }
                            ControlButton { text: "UPDATE"; visible: root.localFor(root.plugin)?.gitManaged ?? false; enabled: !root.busy; onTriggered: root.previewUpdate(root.plugin) }
                            ControlButton { text: "REMOVE"; visible: !!root.localFor(root.plugin)?.id && !(root.localFor(root.plugin)?.managed ?? true); enabled: !root.busy; danger: true; onTriggered: root.ask("remove", root.plugin, "The plugin folder and its nbshell configuration references will be removed.") }
                        }

                        Rule { rowWidth: parent.width; visible: !!root.plugin }
                        SectionHeader { visible: !!root.plugin; text: "RUNTIME"; detail: root.isEnabled(root.localFor(root.plugin)) ? "enabled" : "disabled" }
                        Repeater {
                            model: root.plugin?.kinds ?? []
                            Line {
                                required property string modelData
                                width: parent.width
                                text: modelData.padEnd(13) + root.stateText(root.plugin, modelData)
                                color: text.indexOf("error") >= 0 ? Theme.red : Theme.fgDim
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Rule { rowWidth: parent.width }
                Line { width: parent.width; text: root.statusText !== "" ? root.statusText : "Alt+1/2 tabs · ↑↓ select · Enter enable/install · F5 refresh · Esc close"; color: root.statusError ? Theme.red : Theme.muted; elide: Text.ElideRight }
            }

            Rectangle {
                visible: root.pendingAction !== ""
                anchors.fill: parent
                color: Theme.alpha(Theme.bg, 0.92)
                radius: box.radius
                z: 20

                Column {
                    width: Math.min(parent.width - Theme.spaceXl * 2, Theme.cellW * 62)
                    anchors.centerIn: parent
                    spacing: Theme.spaceMd
                    Line { width: parent.width; text: root.pendingAction.toUpperCase() + " " + (root.pendingItem?.name ?? "PLUGIN") + "?"; color: Theme.fg; font.pixelSize: Theme.fontTitle; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    Line { width: parent.width; text: root.pendingDetail; color: Theme.fgDim; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                    Line { width: parent.width; visible: root.pendingAction === "install"; text: "Third-party QML runs unsandboxed with your user permissions. Review the source before enabling it."; color: Theme.yellow; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spaceMd
                        ControlButton { text: "CANCEL"; onTriggered: root.cancelPending() }
                        ControlButton { text: "CONFIRM"; danger: root.pendingAction === "remove"; onTriggered: root.confirmPending() }
                    }
                }
            }
        }
    }
}
