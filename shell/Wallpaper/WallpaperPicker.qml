import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Visual geometry adapted from Omarchy's ImagePicker at 6ea3215 (MIT).
// nbshell retains collections, temporary desktop preview and dynamic settings.
PanelWindow {
    id: root
    property string query: ""
    property string selectedPath: Config.value("wallpaperOverride", "") || (ThemeIndex.current?.wallpaper ?? "")
    property bool closing: false
    property bool preferencesOpen: false
    property bool livePreview: false
    property bool applying: false
    property string error: ""
    readonly property string scope: Config.value("wallpaperPickerScope", "theme")
    readonly property var list: Wallpapers.list.filter(item => {
        const needle = query.trim().toLocaleLowerCase();
        return (scope === "all" || Wallpapers.themeOf(item) === Config.theme)
            && (!needle || (Wallpapers.nameOf(item) + " " + Wallpapers.themeOf(item)).toLocaleLowerCase().includes(needle));
    })
    readonly property int selected: list.findIndex(item => Wallpapers.pathOf(item) === selectedPath)
    readonly property var current: selected >= 0 ? list[selected] : null
    // These are the upstream image-fan dimensions, not a new control scale.
    readonly property real fit: Math.max(0.1, Math.min(1, (width - Theme.spaceXl * 2) / 900,
        (height - Theme.spaceXl * 2) / (475 + 30 * Theme.menuScale + chromeHeight)))
    readonly property real previewWidth: 768 * fit
    readonly property real previewHeight: 475 * fit
    readonly property real sliceWidth: 108 * fit
    readonly property real sliceHeight: 432 * fit
    readonly property real sliceSpacing: -30 * fit
    readonly property real skew: 28 * fit
    readonly property real chromeHeight: footer.height + Math.round(16 * Theme.menuScale) + Theme.spaceLg
    readonly property real topSpace: 30 * Theme.menuScale * fit

    visible: Runtime.wallpaperOpen
    screen: Compositor.focusedScreen
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nbshell:wallpaperpicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: Runtime.wallpaperOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function label(item) { return Wallpapers.nameOf(item).replace(/\.[^.]+$/, "").replace(/[-_]+/g, " "); }
    function reconcile() {
        if (list.length && !list.some(item => Wallpapers.pathOf(item) === selectedPath))
            selectedPath = Wallpapers.pathOf(list[0]);
        Qt.callLater(updatePreview);
    }
    function select(index) {
        if (!list.length || closing || applying) return;
        selectedPath = Wallpapers.pathOf(list[(index + list.length) % list.length]);
    }
    function move(delta) { select(Math.max(0, selected) + delta); }
    function updatePreview() {
        DynamicWallpaper.pickerPreview = livePreview && !preferencesOpen && !closing && Config.wallpaperEnabled && current
            ? Wallpapers.pathOf(current) : "";
    }
    function setScope(value) {
        if (applying || (value !== "all" && value !== "theme")) return;
        error = "";
        if (!Config.set("wallpaperPickerScope", value)) error = Config.writeError;
    }
    function finishApply() {
        if (!applying || Config.saving) return;
        applying = false;
        if (Config.writeError) error = Config.writeError;
        else close();
    }
    function apply(reset) {
        if (closing || applying || Wallpapers.loading || (!reset && !current)) return;
        error = "";
        applying = true;
        const accepted = reset ? Wallpapers.reset() : Wallpapers.apply(Wallpapers.pathOf(current));
        if (!accepted) {
            applying = false;
            error = Config.writeError || "Could not save wallpaper.";
        } else Qt.callLater(finishApply);
    }
    function close() {
        if (applying) return;
        closing = true;
        DynamicWallpaper.pickerPreview = "";
        Runtime.wallpaperOpen = false;
    }
    function showPreferences() {
        if (applying) return;
        preferencesOpen = true;
        Qt.callLater(() => editor.forceActiveFocus());
    }
    function handleEscape() {
        if (applying) return;
        if (query) query = "";
        else close();
    }
    onListChanged: reconcile()
    onCurrentChanged: updatePreview()
    onLivePreviewChanged: updatePreview()
    onPreferencesOpenChanged: updatePreview()
    Component.onCompleted: {
        Wallpapers.refresh();
        Qt.callLater(() => { reconcile(); keys.forceActiveFocus(); });
    }
    Component.onDestruction: DynamicWallpaper.pickerPreview = ""
    Connections {
        target: Config
        function onSavingChanged() { Qt.callLater(root.finishApply); }
        function onWriteFailed(message) { root.applying = false; root.error = message; }
        function onThemeChanged() { root.applying = false; root.close(); }
    }

    Rectangle { anchors.fill: parent; color: Theme.menuScrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Item {
        id: keys
        visible: !root.preferencesOpen
        anchors.fill: parent
        clip: true
        focus: true
        Accessible.role: Accessible.List
        Accessible.name: "Choose wallpaper"
        Accessible.description: "Type to search. Left, Right or Tab to browse. Enter to apply. F6 for options. Escape to clear search or close. " + (root.current ? root.label(root.current) : "No matches")
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            if (root.applying) { event.accepted = true; return; }
            if (event.key === Qt.Key_F6) {
                if (keys.activeFocus) scopeButton.forceActiveFocus(); else keys.forceActiveFocus();
                event.accepted = true;
                return;
            }
            if (!keys.activeFocus && event.key !== Qt.Key_Escape) return;
            if (event.key === Qt.Key_Escape) root.handleEscape();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!event.isAutoRepeat) root.apply(false);
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier)) root.move(-1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.move(1);
            else if (event.key === Qt.Key_D && event.modifiers & Qt.ControlModifier) root.showPreferences();
            else if (event.key === Qt.Key_R && event.modifiers & Qt.ControlModifier) root.apply(true);
            else if (event.key === Qt.Key_Home) root.select(0);
            else if (event.key === Qt.Key_End) root.select(root.list.length - 1);
            else if (event.key === Qt.Key_Backspace) root.query = event.modifiers & Qt.ControlModifier ? "" : root.query.slice(0, -1);
            else if (event.key === Qt.Key_U && event.modifiers & Qt.ControlModifier) root.query = "";
            else if (event.text && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && event.text.charCodeAt(0) >= 32) root.query += event.text;
            else return;
            event.accepted = true;
        }

        Item {
            id: frame
            anchors.centerIn: parent
            width: parent.width
            height: root.previewHeight + root.topSpace + root.chromeHeight
            MouseArea { anchors.fill: parent; onClicked: {} }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const delta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y) ? event.angleDelta.x : event.angleDelta.y;
                    if (delta !== 0) root.move(delta > 0 ? -1 : 1);
                    event.accepted = true;
                }
            }
            DragHandler {
                id: swipe
                target: null
                yAxis.enabled: false
                property real distance: 0
                onTranslationChanged: if (active) distance = activeTranslation.x
                onActiveChanged: {
                    if (active) distance = 0;
                    else if (Math.abs(distance) > Theme.spaceXl) root.move(distance > 0 ? -1 : 1);
                }
            }
            Item {
                id: carousel
                y: root.topSpace
                width: parent.width
                height: root.previewHeight
                readonly property real previewX: (width - root.previewWidth) / 2
                readonly property real itemStep: root.sliceWidth + root.sliceSpacing
                Repeater {
                    model: root.list
                    delegate: InteractiveSurface {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property int relativeIndex: index - root.selected
                        readonly property bool selected: index === root.selected
                        // Allocate masks/textures only for slices intersecting this output.
                        readonly property bool nearby: x + width >= 0 && x <= carousel.width
                        readonly property string previewPath: Wallpapers.pathOf(modelData)
                        visible: nearby
                        color: "transparent"
                        keyboardFocusable: false
                        accessibleRole: Accessible.ListItem
                        accessibleName: root.label(modelData)
                        accessibleSelected: selected
                        accessibleDescription: selected ? "Apply wallpaper" : "Select wallpaper"
                        onTriggered: {
                            keys.forceActiveFocus();
                            if (selected) root.apply(false); else root.select(index);
                        }
                        x: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.previewWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
                        width: selected ? root.previewWidth : root.sliceWidth
                        height: selected ? root.previewHeight : root.sliceHeight
                        y: selected ? 0 : (root.previewHeight - root.sliceHeight) / 2
                        z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)
                        Item {
                            id: maskShape
                            anchors.fill: parent
                            visible: false
                            layer.enabled: tile.nearby
                            Shape {
                                anchors.fill: parent
                                antialiasing: true
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: "white"
                                    strokeColor: "transparent"
                                    startX: root.skew; startY: 0
                                    PathLine { x: tile.width; y: 0 }
                                    PathLine { x: tile.width - root.skew; y: tile.height }
                                    PathLine { x: 0; y: tile.height }
                                    PathLine { x: root.skew; y: 0 }
                                }
                            }
                        }
                        Item {
                            anchors.fill: parent
                            layer.enabled: tile.nearby
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: maskShape
                                maskThresholdMin: 0.3
                                maskSpreadAtMin: 0.3
                            }
                            Rectangle { anchors.fill: parent; color: Theme.bg }
                            Image {
                                id: wallpaper
                                anchors.fill: parent
                                source: tile.nearby && tile.previewPath ? "file://" + tile.previewPath.split("/").map(encodeURIComponent).join("/") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: Math.round(root.previewWidth * (root.screen?.devicePixelRatio || 1))
                                sourceSize.height: Math.round(root.previewHeight * (root.screen?.devicePixelRatio || 1))
                            }
                            Line {
                                anchors.centerIn: parent
                                width: parent.width * 0.8
                                visible: wallpaper.status !== Image.Ready
                                text: wallpaper.status === Image.Error ? "Image unavailable" : "Loading…"
                                color: Theme.fg
                                font.pixelSize: Theme.audioTitleSize
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bg, tile.selected ? 0 : 0.42) }
                        }
                        Shape {
                            anchors.fill: parent
                            antialiasing: true
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: tile.selected ? Theme.accent : Theme.alpha(Theme.fg, 0.28)
                                strokeWidth: tile.selected ? 3 : 1
                                startX: root.skew; startY: 0
                                PathLine { x: tile.width; y: 0 }
                                PathLine { x: tile.width - root.skew; y: tile.height }
                                PathLine { x: 0; y: tile.height }
                                PathLine { x: root.skew; y: 0 }
                            }
                        }
                        TapHandler { onTapped: tile.activate() }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
            Column {
                id: footer
                anchors.top: carousel.bottom
                anchors.topMargin: Math.round(16 * Theme.menuScale)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(900, parent.width - Theme.spaceXl * 2)
                spacing: Theme.spaceSm
                Line {
                    width: parent.width
                    text: root.current ? root.label(root.current) : (Wallpapers.loading ? "Loading wallpapers…" : (root.query ? "No matches" : "No wallpapers in this collection"))
                    color: Theme.fg
                    style: Text.Outline
                    styleColor: Theme.alpha(Theme.bg, 0.7)
                    font.pixelSize: Theme.audioHeroSize
                    font.family: "sans-serif"
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Line {
                    width: parent.width
                    text: root.error || (root.applying ? "Saving wallpaper…" : root.query ||
                        ((DynamicWallpaper.settings.daytimeEnabled || DynamicWallpaper.settings.image ? "Dynamic active · select fallback · " : "") +
                        (root.current ? Wallpapers.themeOf(root.current) + " · " + (root.selected + 1) + "/" + root.list.length : "Type to search · F6 for options")))
                    color: root.error ? Theme.readable(Theme.red, Theme.bg) : Theme.fg
                    style: Text.Outline
                    styleColor: Theme.alpha(Theme.bg, 0.7)
                    font.pixelSize: Theme.audioTitleSize
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: root.error ? Text.WordWrap : Text.NoWrap
                    elide: root.error ? Text.ElideNone : Text.ElideRight
                }
                Flow {
                    id: options
                    width: Math.min(parent.width, scopeButton.width + previewButton.width + dynamicButton.width + resetButton.width + spacing * 3)
                    x: (parent.width - width) / 2
                    spacing: Theme.spaceSm
                    enabled: !root.applying
                    ControlButton {
                        id: scopeButton
                        text: root.scope === "all" ? "All themes" : "Current theme"
                        accessibleName: "Wallpaper collection"
                        accessibleDescription: "Toggle between this theme and all collections"
                        onTriggered: root.setScope(root.scope === "all" ? "theme" : "all")
                        KeyNavigation.tab: previewButton
                        KeyNavigation.backtab: keys
                    }
                    ControlButton {
                        id: previewButton
                        text: "Desktop preview"
                        accessibleName: "Desktop preview"
                        selected: root.livePreview
                        enabled: Config.wallpaperEnabled
                        onTriggered: root.livePreview = !root.livePreview
                        KeyNavigation.tab: dynamicButton
                        KeyNavigation.backtab: scopeButton
                    }
                    ControlButton {
                        id: dynamicButton
                        text: "Dynamic…"
                        accessibleName: "Dynamic wallpaper settings"
                        onTriggered: root.showPreferences()
                        KeyNavigation.tab: resetButton
                        KeyNavigation.backtab: previewButton
                    }
                    ControlButton {
                        id: resetButton
                        text: "Theme default"
                        accessibleName: "Use theme wallpaper"
                        onTriggered: root.apply(true)
                        KeyNavigation.tab: keys
                        KeyNavigation.backtab: dynamicButton
                    }
                }
            }
        }
    }
    MotionSurface {
        id: preferences
        visible: root.preferencesOpen
        accentBorder: true
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spaceXl * 2, Theme.cellW * 80)
        height: Math.min(parent.height - Theme.spaceXl * 2, editor.implicitHeight + Theme.panelPadding * 2)
        MouseArea { anchors.fill: parent }
        WallpaperSettings {
            id: editor
            anchors.fill: parent
            anchors.margins: Theme.panelPadding
            onBack: {
                root.preferencesOpen = false;
                keys.forceActiveFocus();
            }
        }
    }
}
