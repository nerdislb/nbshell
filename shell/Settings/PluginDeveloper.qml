import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../Widgets/FocusScroll.js" as FocusScroll

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
    property Item pendingFocusItem: null
    property bool busy: false
    property var previewItem: null
    property Item previewFocusItem: null

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

    visible: true
    screen: Compositor.focusedScreen
    color: "transparent"

    WlrLayershell.namespace: "nbshell:plugin-manager"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: Runtime.pluginDeveloperOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function close() { Runtime.pluginDeveloperOpen = false; }
    function requestClose(done) { box.dismiss(done); }
    function requestOpen() { box.enter(); }
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
    function isInstalled(item) { return !!item && (tab === "installed" || !!item.installed); }
    function selectTab(value) {
        tab = value;
        selected = 0;
        statusText = "";
        statusError = false;
        if (value === "porting")
            portingLab.focusInput();
        else
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
    function ask(action, item, detail, opener) {
        pendingFocusItem = opener || keys.Window.window.activeFocusItem;
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
        previewFocusItem = keys.Window.window.activeFocusItem;
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
        if (!item || busy || pendingAction !== "") return;
        if (tab === "store" && !item.installed) {
            if (String(item.repository || "").startsWith("https://"))
                ask("install", item, "The plugin will be cloned but remain disabled until you review and enable it.");
            else {
                statusError = true;
                statusText = "This catalog entry needs an HTTPS repository before it can be installed.";
            }
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

    function moveSelection(delta) {
        const hadRowFocus = pluginRepeater.itemAt(selected)?.activeFocus ?? false;
        selected = Math.max(0, Math.min(list.length - 1, selected + delta));
        if (hadRowFocus) pluginRepeater.itemAt(selected)?.forceActiveFocus();
    }
    function revealSelection() {
        const row = pluginRepeater.itemAt(selected);
        if (row) pluginScroll.contentY = FocusScroll.contentYForFocus(row.y, row.height,
            pluginScroll.contentY, pluginScroll.height, pluginScroll.contentHeight, Theme.spaceSm);
    }
    onSelectedChanged: { Qt.callLater(revealSelection); detailScroll.contentY = 0; }
    onListChanged: { selected = Math.max(0, Math.min(selected, list.length - 1)); Qt.callLater(revealSelection); }
    onVisibleChanged: {
        if (visible) {
            tab = Runtime.pluginManagerTab;
            selected = 0;
            Plugins.refresh();
            if (tab === "porting")
                portingLab.focusInput();
            else
                Qt.callLater(search.forceActiveFocus);
        } else {
            cancelPending();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.scrim; opacity: box.opacity }
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
                root.previewFocusItem = null;
                return;
            }
            const clipped = output.length > 1400 ? output.slice(0, 1400) + "\n…" : output;
            const item = root.previewItem;
            const opener = root.previewFocusItem;
            root.previewItem = null;
            root.previewFocusItem = null;
            root.ask("update", item, clipped, opener);
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
        Keys.onUpPressed: if (root.tab !== "porting") root.moveSelection(-1)
        Keys.onDownPressed: if (root.tab !== "porting") root.moveSelection(1)
        // Auto-Repeat sperren: die Aktion installiert oder aktiviert ein Plugin
        // und darf von einem gehaltenen Enter nicht mehrfach ausgeloest werden.
        Keys.onReturnPressed: event => {
            if (!event.isAutoRepeat && root.tab !== "porting") root.primaryAction(root.plugin);
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            if (!event.isAutoRepeat && root.tab !== "porting") root.primaryAction(root.plugin);
            event.accepted = true;
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_1) { root.selectTab("installed"); event.accepted = true; }
            if (event.key === Qt.Key_2) { root.selectTab("store"); event.accepted = true; }
            if (event.key === Qt.Key_3) { root.selectTab("porting"); event.accepted = true; }
            if (event.key === Qt.Key_F5) { Plugins.refresh(); event.accepted = true; }
        }

        OverlaySurface {
            id: box
            color: Theme.bg
            border.color: Theme.panelBorder
            accentBorder: false
            motionEnabled: false
            preferredWidth: Theme.cellW * 104
            preferredHeight: Theme.cellH * 39
            MouseArea { anchors.fill: parent }

            Column {
                id: pluginContent
                readonly property real bodyHeight: Math.max(0, height - pluginHead.height - tabsRow.height - topRule.height - bottomRule.height - footerRow.height - (search.visible ? search.height : 0) - spacing * (search.visible ? 6 : 5))
                anchors.fill: parent
                anchors.margins: Theme.spaceLg
                spacing: Theme.spaceSm

                Column {
                    id: pluginHead
                    width: parent.width
                    spacing: Theme.spaceXs
                    PanelHead { rowWidth: parent.width; title: "Plugins" }
                    Line {
                        width: parent.width
                        text: root.tab === "porting"
                            ? "Assess public community sources before deciding to port"
                            : "Installed modules and the curated nbshell store"
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontCaption
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: tabsRow
                    width: parent.width
                    height: Theme.controlHeight
                    spacing: Theme.spaceSm

                    ControlButton { id: installedTab; text: "Installed"; selected: root.tab === "installed"; onTriggered: root.selectTab("installed") }
                    ControlButton { id: storeTab; text: "Store"; selected: root.tab === "store"; onTriggered: root.selectTab("store") }
                    ControlButton { id: portingTab; text: "Porting Lab"; selected: root.tab === "porting"; onTriggered: root.selectTab("porting") }

                }

                TextField {
                    id: search
                    width: parent.width
                    height: Theme.controlHeight
                    visible: root.tab !== "porting"
                    placeholderText: "Search plugins…"
                    accessibleName: "Search plugins"
                    accessibleDescription: "Filters installed and store plugins"
                    text: root.query
                    background: null
                    KeyNavigation.tab: pluginRepeater.itemAt(root.selected) || closeButton
                    onTextEdited: root.query = text
                    Keys.onPressed: event => {
                        if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
                            root.selectTab(["installed", "store", "porting"][event.key - Qt.Key_1]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_F5) {
                            Plugins.refresh(); event.accepted = true;
                        }
                    }
                }

                Rule { id: topRule; rowWidth: parent.width }

                Row {
                    id: browser
                    visible: root.tab !== "porting"
                    width: parent.width
                    height: pluginContent.bodyHeight
                    spacing: Theme.spaceLg

                    Flickable {
                        id: pluginScroll
                        width: Math.floor((parent.width - parent.spacing * 2 - Theme.borderWidth) * 0.4)
                        height: parent.height
                        contentWidth: width
                        contentHeight: pluginRows.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        onContentHeightChanged: Qt.callLater(root.revealSelection)
                        onHeightChanged: Qt.callLater(root.revealSelection)

                        Column {
                            id: pluginRows
                            width: pluginScroll.width - Theme.spaceMd
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
                                id: pluginRepeater
                                model: root.list
                                PanelRow {
                                    required property var modelData
                                    required property int index
                                    width: pluginRows.width
                                    height: Theme.controlHeight * 2
                                    interactive: true
                                    keyboardFocusable: selected
                                    KeyNavigation.tab: primaryButton.enabled ? primaryButton : closeButton
                                    KeyNavigation.backtab: search
                                    title: modelData.name
                                    detail: modelData.id
                                    value: root.isEnabled(modelData) ? "on" : ""
                                    selected: index === root.selected
                                    tone: Theme.fg
                                    color: selected || hovered ? Theme.mix(Theme.bg, Theme.fg, 0.08) : "transparent"
                                    border.width: activeFocus ? Theme.borderWidth : 0
                                    contentLeftPadding: Theme.spaceSm
                                    onTriggered: root.selected = index
                                    onActiveFocusChanged: if (activeFocus) { root.selected = index; root.revealSelection(); }
                                }
                            }
                        }
                    }

                    Rectangle { width: Theme.borderWidth; height: parent.height; color: Theme.panelBorder }

                    Flickable {
                        id: detailScroll
                        width: parent.width - pluginScroll.width - Theme.borderWidth - parent.spacing * 2
                        height: parent.height
                        contentWidth: width
                        contentHeight: details.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        function reveal(item) {
                            const p = item.mapToItem(contentItem, 0, 0);
                            contentY = FocusScroll.contentYForFocus(p.y, item.height, contentY, height, contentHeight, Theme.spaceSm);
                        }
                        Column {
                            id: details
                            width: detailScroll.width - Theme.spaceMd
                            spacing: Theme.spaceSm

                            Line { width: parent.width; text: root.plugin?.name ?? "Select a plugin"; color: Theme.fg; font.pixelSize: Theme.fontTitle; font.bold: true; elide: Text.ElideRight }
                            Line { width: parent.width; visible: !!root.plugin; text: root.plugin?.description ?? ""; color: Theme.fgDim; wrapMode: Text.Wrap }
                            Rule { rowWidth: parent.width }
                            Line { width: parent.width; visible: !!root.plugin; text: "ID          " + (root.plugin?.id ?? ""); color: Theme.fgDim; elide: Text.ElideMiddle }
                            Line { width: parent.width; visible: !!root.plugin; text: "AUTHOR      " + (root.plugin?.author || "Unknown"); color: Theme.fgDim; elide: Text.ElideRight }
                            Line { width: parent.width; visible: !!root.plugin; text: "LICENSE     " + (root.plugin?.license || "Not declared"); color: root.plugin?.license ? Theme.fgDim : Theme.yellow; elide: Text.ElideRight }
                            Line { width: parent.width; visible: !!root.plugin; text: "SOURCE      " + (!root.isInstalled(root.plugin) ? "Not installed" : root.plugin?.managed ? "Bundled with nbshell" : (root.plugin?.gitManaged ? "Git checkout" : "Local folder")); color: Theme.fgDim; wrapMode: Text.Wrap }
                            Line { width: parent.width; visible: !!root.plugin; text: "REQUIRES    " + root.dependencyText(root.plugin); color: Theme.fgDim; wrapMode: Text.Wrap }
                            Line { width: parent.width; visible: !!root.plugin; text: "KINDS       " + ((root.plugin?.kinds ?? []).join(" · ") || "—"); color: Theme.fgDim; elide: Text.ElideRight }

                            Flow {
                                width: parent.width
                                visible: !!root.plugin
                                spacing: Theme.spaceSm
                                ControlButton { id: primaryButton; onActiveFocusChanged: if (activeFocus) detailScroll.reveal(this); text: root.actionLabel(root.plugin); enabled: !root.busy; selected: root.isEnabled(root.localFor(root.plugin)); onTriggered: root.primaryAction(root.plugin) }
                                ControlButton { onActiveFocusChanged: if (activeFocus) detailScroll.reveal(this); text: "SOURCE"; enabled: root.repositoryUrl(root.plugin) !== ""; onTriggered: Quickshell.execDetached(["xdg-open", root.repositoryUrl(root.plugin)]) }
                                ControlButton { onActiveFocusChanged: if (activeFocus) detailScroll.reveal(this); text: "UPDATE"; visible: root.localFor(root.plugin)?.gitManaged ?? false; enabled: !root.busy; onTriggered: root.previewUpdate(root.plugin) }
                                ControlButton { onActiveFocusChanged: if (activeFocus) detailScroll.reveal(this); id: removeButton; text: "REMOVE"; visible: root.isInstalled(root.plugin) && !(root.localFor(root.plugin)?.managed ?? true); enabled: !root.busy; danger: true; onTriggered: root.ask("remove", root.plugin, "The plugin folder and its nbshell configuration references will be removed.") }
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
                }

                PluginPortingLab {
                    id: portingLab
                    visible: root.tab === "porting"
                    width: parent.width
                    height: pluginContent.bodyHeight
                }

                Rule { id: bottomRule; rowWidth: parent.width }
                Row {
                    id: footerRow
                    width: parent.width
                    height: Math.max(footerText.implicitHeight, closeButton.height)
                    spacing: Theme.spaceMd
                    Line {
                        id: footerText
                        width: parent.width - closeButton.width - parent.spacing
                        text: root.tab === "porting"
                            ? "Alt+1/2/3 tabs · Enter analyze · report: j/k or arrows scroll · Esc close"
                            : (root.statusText !== "" ? root.statusText : "Alt+1/2/3 tabs · ↑↓ select · Tab actions · F5 refresh · Esc close")
                        color: root.statusError ? Theme.red : Theme.muted
                        font.pixelSize: Theme.fontCaption
                        wrapMode: Text.Wrap
                    }
                    ActionButton { id: closeButton; text: "Close"; onTriggered: root.close() }
                }
            }

            ModalSurface {
                id: confirmationModal

                visible: root.pendingAction !== ""
                anchors.fill: parent
                z: 20
                blockedItem: pluginContent
                initialFocusItem: cancelConfirmation
                restoreFocusItem: root.pendingFocusItem
                dialogTitle: root.pendingAction.toUpperCase() + " "
                    + (root.pendingItem?.name ?? "PLUGIN") + "?"
                dialogDescription: root.pendingDetail
                preferredWidth: Theme.cellW * 62
                preferredHeight: Math.min(Theme.cellH * 24, confirmationTitle.implicitHeight + confirmationDetail.implicitHeight + (confirmationWarning.visible ? confirmationWarning.implicitHeight : 0) + confirmationButtons.height + Theme.panelPadding * 2 + Theme.spaceMd * (confirmationWarning.visible ? 3 : 2))
                scrimRadius: box.radius
                closeOnScrim: false
                onCloseRequested: root.cancelPending()
                Connections { target: confirmationModal; function onVisibleChanged() { if (confirmationModal.visible) confirmationScroll.contentY = 0; } }
                Keys.onPressed: event => {
                    if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown].indexOf(event.key) < 0) return;
                    const direction = event.key === Qt.Key_Up || event.key === Qt.Key_PageUp ? -1 : 1;
                    confirmationScroll.contentY = Math.max(0, Math.min(confirmationScroll.contentHeight - confirmationScroll.height,
                        confirmationScroll.contentY + direction * (event.key === Qt.Key_Up || event.key === Qt.Key_Down ? Theme.rowHeight : confirmationScroll.height)));
                    event.accepted = true;
                }

                Column {
                    id: confirmationContent

                    anchors.fill: parent
                    anchors.margins: Theme.panelPadding
                    spacing: Theme.spaceMd
                    Line {
                        id: confirmationTitle
                        width: parent.width
                        text: root.pendingAction.toUpperCase() + " " + (root.pendingItem?.name ?? "PLUGIN") + "?"
                        color: Theme.fg
                        font.pixelSize: Theme.fontTitle
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Flickable {
                        id: confirmationScroll
                        width: parent.width
                        height: Math.max(0, parent.height - confirmationTitle.height - confirmationButtons.height - (confirmationWarning.visible ? confirmationWarning.height : 0) - parent.spacing * (confirmationWarning.visible ? 3 : 2))
                        contentWidth: width
                        contentHeight: confirmationDetail.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        Line { id: confirmationDetail; width: parent.width - Theme.spaceMd; text: root.pendingDetail; color: Theme.fgDim; wrapMode: Text.Wrap }
                    }
                    Line {
                        id: confirmationWarning
                        width: parent.width
                        visible: root.pendingAction === "install"
                        text: "Third-party QML runs unsandboxed with your user permissions. Review the source before enabling it."
                        color: Theme.yellow
                        wrapMode: Text.WordWrap
                    }
                    Row {
                        id: confirmationButtons
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spaceMd
                        ControlButton { id: cancelConfirmation; text: "CANCEL"; onTriggered: root.cancelPending() }
                        ControlButton { text: "CONFIRM"; danger: root.pendingAction === "remove"; onTriggered: root.confirmPending() }
                    }
                }
            }
        }
    }
}
