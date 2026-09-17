import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: root
    color: "transparent"
    readonly property bool atTop: Config.edge === "bottom"
    readonly property string outputName: screen?.name ?? ""
    readonly property bool fullscreen: (ToplevelManager.toplevels?.values ?? []).some(t =>
        t.fullscreen && t.activated && t.screens.some(s => s.name === root.outputName))
    readonly property bool preview: DockService.previewActive && Config.dockEnabled
        && outputName === (Compositor.focusedScreen?.name ?? "")
    readonly property bool blocked: fullscreen || (Runtime.settingsOpen && !preview) || Runtime.launcherOpen
        || (Runtime.menuOpen && !preview) || Runtime.powerOpen
    property bool shown: false
    property real revealProgress: (shown || preview) && !blocked ? 1 : 0
    Behavior on revealProgress {
        NumberAnimation { duration: root.shown ? Theme.motionEnter : Theme.motionExit; easing.type: Easing.OutCubic }
    }
    property bool keyboardMode: false
    property bool dismissed: false
    property string menuKey: ""
    readonly property var menuGroup: DockService.groups.find(g => g.key === menuKey) ?? null
    property var menuWindowIds: []
    readonly property bool inside: edgeHover.hovered || frameHover.hovered
    readonly property real dockPadding: Math.round(Theme.spaceSm * DockService.dockScale / 100)
    readonly property real dockSpacing: Math.round(Theme.spaceXs * DockService.dockScale / 100)
    readonly property real glyphSize: Math.round((Theme.controlHeight - Theme.spaceXs) * DockService.dockIconScale / 100)
    readonly property real iconSize: Math.max(Math.round((Theme.controlHeight + Theme.spaceXl) * DockService.dockScale / 100), glyphSize + dockPadding * 2)
    // Interaction delays, not animation durations. Leave hysteresis allows a
    // deliberate move from an icon into its window chooser.
    readonly property int revealDelay: 120
    readonly property int leaveDelay: 650

    WlrLayershell.namespace: "nbshell:dock"
    WlrLayershell.layer: preview ? WlrLayershell.Overlay : WlrLayershell.Top
    // Only an explicit menu click or keyboard reveal takes the keyboard.
    // Changing an already-mapped panel to OnDemand does not acquire focus
    // reliably on Umbriel; release the exclusive request on every dismiss.
    WlrLayershell.keyboardFocus: !preview && (keyboardMode || menuKey !== "") ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.top: atTop
    anchors.bottom: !atTop
    implicitWidth: Math.max(1, (screen?.width ?? 800) - Theme.spaceLg * 2)
    implicitHeight: Math.max(1, Math.min(Theme.cellH * 24, (screen?.height ?? 600) - Theme.barHeight - Theme.spaceLg * 2))

    // Stable layer geometry. Only the visible content and the tiny center-edge
    // hotspot accept input; transparent areas remain click-through throughout.
    mask: Region {
        Region { item: hotspot }
        Region {
            x: frame.x + dockBody.x; y: frame.y + dockBody.y
            width: root.blocked || root.preview ? 0 : dockBody.width; height: dockBody.height
        }
        Region {
            x: frame.x + menu.x; y: frame.y + menu.y
            width: root.blocked || root.preview || !menu.visible ? 0 : menu.width; height: menu.height
        }
    }

    function publish() {
        if (!outputName) return;
        DockService.report(outputName, {shown: (shown || preview) && !blocked, preview: preview,
            blocked: blocked, menu: menuKey !== "", edge: atTop ? "top" : "bottom", keyboard: keyboardMode,
            width: dockBody.width, height: dockBody.height, iconSize: glyphSize});
    }
    function dismiss() {
        revealTimer.stop();
        leaveTimer.stop();
        // Suppress immediate re-entry only if the pointer is still inside.
        // A programmatic close/edge change while outside must not consume the
        // user's next deliberate visit to the hotspot.
        dismissed = inside;
        shown = false;
        keyboardMode = false;
        menuKey = "";
    }
    function reveal(keyboard) {
        if (blocked || preview) return;
        dismissed = false;
        shown = true;
        keyboardMode = keyboard;
        if (keyboard) Qt.callLater(() => launcher.forceActiveFocus(Qt.TabFocusReason));
    }
    function updateHover() {
        if (!inside) {
            dismissed = false;
            revealTimer.stop();
            if (shown && !keyboardMode) leaveTimer.restart();
        } else {
            leaveTimer.stop();
            if (!shown && !dismissed && !blocked && !revealTimer.running) revealTimer.start();
        }
    }
    function openMenu(group) {
        if (!group || blocked) return;
        menuKey = menuKey === group.key ? "" : group.key;
        if (menuKey) Qt.callLater(() => (windowRows.itemAt(0) || pinButton).forceActiveFocus(Qt.TabFocusReason));
    }
    function activate(group) {
        if (group.windows.length > 1) openMenu(group);
        else if (group.windows.length === 1) DockService.focusWindow(group.windows[0].id);
        else if (group.entry) DockService.launch(group.entry);
    }
    onInsideChanged: updateHover()
    onPreviewChanged: { dismiss(); publish(); }
    onGlyphSizeChanged: Qt.callLater(publish)
    onAtTopChanged: { dismiss(); publish(); }
    onBlockedChanged: { if (blocked) dismiss(); publish(); }
    onShownChanged: publish()
    onMenuKeyChanged: {
        publish();
        if (!menuKey && keyboardMode && shown)
            Qt.callLater(() => launcher.forceActiveFocus(Qt.TabFocusReason));
    }
    onKeyboardModeChanged: publish()
    onMenuGroupChanged: {
        const next = (menuGroup?.windows ?? []).map(w => String(w.id));
        if (JSON.stringify(next) !== JSON.stringify(menuWindowIds)) menuWindowIds = next;
        if (!menuGroup && menuKey) menuKey = "";
    }
    onMenuWindowIdsChanged: {
        if (menuKey && shown)
            Qt.callLater(() => (windowRows.itemAt(0) || pinButton).forceActiveFocus(Qt.TabFocusReason));
    }
    Component.onCompleted: publish()
    Component.onDestruction: DockService.report(outputName, null)
    Connections {
        target: DockService
        function onHideRequested() { root.dismiss(); }
        function onGroupKeysChanged() {
            if (root.keyboardMode && root.shown && !root.menuKey)
                Qt.callLater(() => launcher.forceActiveFocus(Qt.TabFocusReason));
        }
        function onRevealRequested(output) {
            if (root.outputName === output) root.reveal(true);
            else root.dismiss();
        }
    }
    Timer { id: revealTimer; interval: root.revealDelay; onTriggered: { if (root.inside && !root.dismissed) root.reveal(false); } }
    Timer { id: leaveTimer; interval: root.leaveDelay; onTriggered: { if (!root.inside && !root.keyboardMode) root.dismiss(); } }

    Item {
        id: hotspot
        width: root.blocked || root.preview ? 0 : Math.min(Theme.cellW * 20, dockBody.width)
        height: Math.max(2, Theme.borderWidth * 2)
        x: (root.width - width) / 2
        y: root.atTop ? 0 : root.height - height
        HoverHandler { id: edgeHover }
    }

    Item {
        id: frame
        width: Math.max(dockBody.width, root.menuGroup ? menu.width : 0)
        height: dockBody.height + Theme.spaceSm * 2 + (root.menuGroup ? menu.height : 0)
        x: (root.width - width) / 2
        y: root.atTop ? -height * (1 - root.revealProgress) : root.height - height * root.revealProgress
        enabled: root.shown && !root.blocked && !root.preview
        HoverHandler { id: frameHover }
        Keys.onEscapePressed: root.dismiss()

        PanelSurface {
            id: dockBody
            width: Math.min(root.width, appRow.width + launcher.width + root.dockSpacing + root.dockPadding * 2)
            height: root.iconSize + root.dockPadding * 2
            onWidthChanged: Qt.callLater(root.publish)
            onHeightChanged: Qt.callLater(root.publish)
            x: (parent.width - width) / 2
            y: root.atTop ? Theme.spaceSm : parent.height - height - Theme.spaceSm
            DockIcon {
                id: launcher
                x: root.dockPadding
                y: root.dockPadding
                width: root.iconSize; height: width
                glyphSize: root.glyphSize
                label: "Applications"
                fallback: Icons.matrix
                onTriggered: { root.dismiss(); Runtime.openLauncher(); }
                onContextRequested: { root.dismiss(); Runtime.settingsOpen = true; }
            }
            Flickable {
                id: appViewport
                x: launcher.x + launcher.width + root.dockSpacing
                y: root.dockPadding
                width: Math.max(0, parent.width - x - root.dockPadding)
                height: root.iconSize
                contentWidth: appRow.width
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                Row {
                    id: appRow
                    spacing: root.dockSpacing
                    Repeater {
                        model: DockService.groupKeys
                        DockIcon {
                            id: appIcon
                            required property var modelData
                            readonly property var group: DockService.groups.find(g => g.key === modelData)
                            width: root.iconSize; height: width
                            glyphSize: root.glyphSize
                            label: group?.name ?? "Application"
                            iconSource: Apps.iconFor(group?.entry)
                            running: (group?.windows.length ?? 0) > 0
                            selected: (group?.windows ?? []).some(w => w.is_active)
                            onActiveFocusChanged: {
                                if (!activeFocus) return;
                                if (x < appViewport.contentX) appViewport.contentX = x;
                                else if (x + width > appViewport.contentX + appViewport.width)
                                    appViewport.contentX = x + width - appViewport.width;
                            }
                            onTriggered: { if (group) root.activate(group); }
                            onContextRequested: root.openMenu(group)
                        }
                    }
                }
            }
        }
        PanelSurface {
            id: menu
            visible: root.menuGroup !== null
            width: Math.min(root.width, Theme.cellW * 44)
            height: Math.min(menuColumn.height + Theme.spaceSm * 2, root.height - dockBody.height - Theme.spaceSm * 3)
            x: (parent.width - width) / 2
            y: root.atTop ? dockBody.y + dockBody.height + Theme.spaceSm : 0
            Flickable {
                anchors.fill: parent
                anchors.margins: Theme.spaceSm
                contentHeight: menuColumn.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Column {
                    id: menuColumn
                    width: parent.width
                    spacing: Theme.spaceXs
                    Repeater {
                        id: windowRows
                        model: root.menuWindowIds
                        PanelRow {
                            required property var modelData
                            readonly property var windowData: root.menuGroup?.windows.find(w => String(w.id) === modelData)
                            width: menuColumn.width
                            title: windowData?.title || root.menuGroup?.name || "Window"
                            selected: windowData?.is_active ?? false
                            interactive: true
                            onTriggered: DockService.focusWindow(modelData)
                            onActiveFocusChanged: if (activeFocus) {
                                const view = menuColumn.parent;
                                view.contentY = Math.max(0, Math.min(y, view.contentHeight - view.height));
                            }
                        }
                    }
                    PanelRow {
                        id: pinButton
                        width: menuColumn.width
                        visible: !!root.menuGroup?.entry
                        title: root.menuGroup?.pinned ? "Unpin from dock" : "Pin to dock"
                        interactive: true
                        onTriggered: {
                            DockService.pin(root.menuGroup);
                            root.menuKey = "";
                            if (root.keyboardMode) Qt.callLater(() => launcher.forceActiveFocus(Qt.TabFocusReason));
                        }
                    }
                    PanelRow {
                        width: menuColumn.width
                        visible: !!root.menuGroup?.entry
                        title: "Open new instance"
                        interactive: true
                        onTriggered: DockService.launch(root.menuGroup?.entry)
                    }
                    PanelRow {
                        width: menuColumn.width
                        visible: root.menuWindowIds.length > 0
                        title: root.menuWindowIds.length > 1 ? "Close all windows" : "Close"
                        interactive: true
                        onTriggered: DockService.closeGroup(root.menuKey)
                        onActiveFocusChanged: if (activeFocus) {
                            const view = menuColumn.parent;
                            view.contentY = Math.max(0, Math.min(y, view.contentHeight - view.height));
                        }
                    }
                }
            }
        }
    }
}
